//! macOS Vision framework OCR via `macocr` subprocess.
//!
//! Architecture choice rationale: DECISIONS.md "OCR 구현 방식". Briefly:
//! we shell out to the `macocr` Rust binary (cargo install macocr) instead of
//! linking objc2-vision directly. Saves 8-10h of cocoa interop and matches
//! the ClaudeCliDispatcher subprocess pattern.
//!
//! v0.2 upgrade path: wrap this behind an `OcrProvider` trait and swap to
//! objc2-vision direct bindings when subprocess overhead becomes the
//! bottleneck.
//!
//! SPEC rule 4 violation (new module not in SPEC tree) recorded in
//! SCRATCHPAD — justified by dogfooding accuracy measurement (70% → 95-99%
//! requires deterministic coords).

use serde::Deserialize;
use std::path::Path;
use uuid::Uuid;

#[derive(Debug, Clone, Deserialize)]
pub struct OcrBox {
    pub text: String,
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

#[derive(Debug, Clone, Deserialize)]
struct MacocrEnvelope {
    #[serde(default)]
    success: Option<bool>,
    #[serde(default)]
    message: Option<String>,
    #[serde(default)]
    image_width: Option<i32>,
    #[serde(default)]
    image_height: Option<i32>,
    #[serde(default)]
    ocr_boxes: Vec<OcrBox>,
}

#[derive(Debug)]
pub enum OcrError {
    NotInstalled,
    Spawn(String),
    NonZeroExit { code: Option<i32>, stderr: String },
    Parse(String),
    Io(std::io::Error),
}

impl std::fmt::Display for OcrError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotInstalled => write!(
                f,
                "macocr binary not found in PATH. Run `cargo install macocr`."
            ),
            Self::Spawn(e) => write!(f, "macocr spawn: {e}"),
            Self::NonZeroExit { code, stderr } => {
                write!(f, "macocr exit {code:?}: {}", stderr.chars().take(300).collect::<String>())
            }
            Self::Parse(e) => write!(f, "macocr stdout parse: {e}"),
            Self::Io(e) => write!(f, "ocr io: {e}"),
        }
    }
}

impl std::error::Error for OcrError {}

impl From<std::io::Error> for OcrError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e)
    }
}

const MACOCR_BINARY: &str = "macocr";

/// Run macocr on PNG bytes, return list of (text, bbox) in pixel units of
/// the *input* image. Caller is responsible for matching those to whatever
/// monitor/CSS coord system they end up rendering in.
pub async fn ocr_png(png_bytes: &[u8]) -> Result<Vec<OcrBox>, OcrError> {
    let temp_dir = std::env::temp_dir();
    let temp_name = format!("sb-ocr-{}.png", Uuid::new_v4());
    let temp_path = temp_dir.join(&temp_name);
    tokio::fs::write(&temp_path, png_bytes).await?;
    let result = run_macocr(&temp_path).await;
    let _ = tokio::fs::remove_file(&temp_path).await;
    result
}

async fn run_macocr(path: &Path) -> Result<Vec<OcrBox>, OcrError> {
    let output = tokio::process::Command::new(MACOCR_BINARY)
        .arg(path)
        .output()
        .await
        .map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                OcrError::NotInstalled
            } else {
                OcrError::Spawn(e.to_string())
            }
        })?;

    if !output.status.success() {
        return Err(OcrError::NonZeroExit {
            code: output.status.code(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        });
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let envelope: MacocrEnvelope = serde_json::from_str(&stdout).map_err(|e| {
        OcrError::Parse(format!(
            "{e}; stdout[..400]={}",
            stdout.chars().take(400).collect::<String>()
        ))
    })?;
    if envelope.success == Some(false) {
        return Err(OcrError::NonZeroExit {
            code: None,
            stderr: envelope.message.unwrap_or_default(),
        });
    }
    tracing::info!(
        target: "ocr",
        "macocr ok: img={}x{}, boxes={}",
        envelope.image_width.unwrap_or(-1),
        envelope.image_height.unwrap_or(-1),
        envelope.ocr_boxes.len()
    );
    Ok(envelope.ocr_boxes)
}

/// Substring + lowercase matching to find an OCR box for the LLM-named
/// element. Returns the best (largest text-overlap) match.
///
/// macocr returns text *lines*, not individual words — when the LLM says
/// "Create API Key" we look for any box whose `text` contains that phrase
/// (case-insensitive), or any phrase that contains a unique subsequence of
/// the target.
pub fn find_box<'a>(boxes: &'a [OcrBox], target: &str) -> Option<&'a OcrBox> {
    let target_lc = target.to_lowercase();
    let target_trim = target_lc.trim();
    if target_trim.is_empty() {
        return None;
    }

    // 1. Exact (case-insensitive) text match.
    if let Some(b) = boxes
        .iter()
        .find(|b| b.text.to_lowercase().trim() == target_trim)
    {
        return Some(b);
    }
    // 2. Box text contains target. Pick longest text (closer to full label).
    let mut contains: Vec<&OcrBox> = boxes
        .iter()
        .filter(|b| b.text.to_lowercase().contains(target_trim))
        .collect();
    contains.sort_by_key(|b| std::cmp::Reverse(b.text.len()));
    if let Some(b) = contains.first() {
        return Some(b);
    }
    // 3. Target contains box text (target is longer phrase that includes the
    //    label, e.g., "Create API Key 버튼"). Pick longest box text.
    let mut contained: Vec<&OcrBox> = boxes
        .iter()
        .filter(|b| !b.text.is_empty() && target_trim.contains(&b.text.to_lowercase()))
        .collect();
    contained.sort_by_key(|b| std::cmp::Reverse(b.text.len()));
    contained.first().copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_boxes() -> Vec<OcrBox> {
        vec![
            OcrBox { text: "Create API Key".into(), x: 1290, y: 425, w: 198, h: 36 },
            OcrBox { text: "Manage your project API keys".into(), x: 100, y: 380, w: 800, h: 24 },
            OcrBox { text: "jarvis-pc".into(), x: 100, y: 500, w: 120, h: 20 },
        ]
    }

    #[test]
    fn find_exact_match() {
        let boxes = fake_boxes();
        let b = find_box(&boxes, "Create API Key").unwrap();
        assert_eq!(b.x, 1290);
    }

    #[test]
    fn find_case_insensitive() {
        let boxes = fake_boxes();
        let b = find_box(&boxes, "create api key").unwrap();
        assert_eq!(b.x, 1290);
    }

    #[test]
    fn find_substring() {
        let boxes = fake_boxes();
        let b = find_box(&boxes, "API Key").unwrap();
        // Both first and second box contain "api key" lowercase. Picks longer one.
        assert!(b.text.contains("Create") || b.text.contains("Manage"));
    }

    #[test]
    fn find_with_korean_suffix() {
        // LLM이 흔히 "Create API Key 버튼" 식으로 답함. box 텍스트는 그냥 "Create API Key".
        let boxes = fake_boxes();
        let b = find_box(&boxes, "Create API Key 버튼").unwrap();
        assert_eq!(b.text, "Create API Key");
    }

    #[test]
    fn no_match_returns_none() {
        let boxes = fake_boxes();
        assert!(find_box(&boxes, "Nonexistent Element").is_none());
    }

    #[test]
    fn empty_target_returns_none() {
        let boxes = fake_boxes();
        assert!(find_box(&boxes, "  ").is_none());
    }
}

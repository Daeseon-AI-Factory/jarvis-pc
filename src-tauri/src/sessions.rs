use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use time::format_description::well_known::Iso8601;
use time::macros::format_description;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::dispatcher::AnalysisResult;

#[derive(Debug, Serialize, Deserialize)]
pub struct Meta {
    pub timestamp_unix: u64,
    pub timestamp_iso: String,
    pub feedback: Option<String>,
}

#[derive(Debug)]
pub enum SessionError {
    Io(std::io::Error),
    Serialize(serde_json::Error),
    Time(String),
}

impl std::fmt::Display for SessionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(e) => write!(f, "session io: {e}"),
            Self::Serialize(e) => write!(f, "session serialize: {e}"),
            Self::Time(e) => write!(f, "session time: {e}"),
        }
    }
}

impl std::error::Error for SessionError {}

impl From<std::io::Error> for SessionError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<serde_json::Error> for SessionError {
    fn from(e: serde_json::Error) -> Self {
        Self::Serialize(e)
    }
}

/// Persist a single analyze() invocation under `base/<YYYY-MM-DD>/<uuid>/`.
/// Returns the directory so callers can log where the session landed.
pub fn save_session(
    base: &Path,
    image: &[u8],
    instruction: &str,
    result: &AnalysisResult,
) -> Result<PathBuf, SessionError> {
    let now = SystemTime::now();
    let unix = now
        .duration_since(SystemTime::UNIX_EPOCH)
        .map_err(|e| SessionError::Time(e.to_string()))?
        .as_secs();
    let utc = OffsetDateTime::now_utc();
    let date = utc
        .format(format_description!("[year]-[month]-[day]"))
        .map_err(|e| SessionError::Time(e.to_string()))?;
    let iso = utc
        .format(&Iso8601::DEFAULT)
        .map_err(|e| SessionError::Time(e.to_string()))?;

    let dir = base.join(date).join(Uuid::new_v4().to_string());
    std::fs::create_dir_all(&dir)?;

    std::fs::write(dir.join("screen.png"), image)?;
    std::fs::write(dir.join("instruction.txt"), instruction)?;
    std::fs::write(
        dir.join("response.json"),
        serde_json::to_string_pretty(result)?,
    )?;
    std::fs::write(
        dir.join("meta.json"),
        serde_json::to_string_pretty(&Meta {
            timestamp_unix: unix,
            timestamp_iso: iso,
            feedback: None,
        })?,
    )?;

    tracing::info!(target: "sessions", "saved: {:?}", dir);
    Ok(dir)
}

/// Update meta.json's feedback field for an already-saved session.
pub fn record_feedback(session_dir: &Path, value: &str) -> Result<(), SessionError> {
    let meta_path = session_dir.join("meta.json");
    let text = std::fs::read_to_string(&meta_path)?;
    let mut meta: Meta = serde_json::from_str(&text)?;
    meta.feedback = Some(value.to_string());
    std::fs::write(&meta_path, serde_json::to_string_pretty(&meta)?)?;
    tracing::info!(target: "sessions", "feedback={} for {:?}", value, session_dir);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_base() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("sb-test-{}", Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn save_session_writes_four_files() {
        let base = tmp_base();
        let result = AnalysisResult {
            screen_state: Some("test".into()),
            next_action: Some("click X".into()),
            coordinates: Some([10, 20, 30, 40]),
            reasoning: None,
            raw: "{...}".into(),
        };
        let dir =
            save_session(&base, b"\x89PNG\r\n\x1a\n_fake_", "hello", &result).expect("save");
        for name in &["screen.png", "instruction.txt", "response.json", "meta.json"] {
            assert!(dir.join(name).exists(), "missing {name}");
        }
        let instr = std::fs::read_to_string(dir.join("instruction.txt")).unwrap();
        assert_eq!(instr, "hello");
        let meta: Meta =
            serde_json::from_str(&std::fs::read_to_string(dir.join("meta.json")).unwrap()).unwrap();
        assert!(meta.feedback.is_none());

        std::fs::remove_dir_all(base).ok();
    }

    #[test]
    fn record_feedback_updates_meta() {
        let base = tmp_base();
        let result = AnalysisResult::default();
        let dir = save_session(&base, b"png", "i", &result).expect("save");
        record_feedback(&dir, "up").expect("feedback");
        let meta: Meta =
            serde_json::from_str(&std::fs::read_to_string(dir.join("meta.json")).unwrap()).unwrap();
        assert_eq!(meta.feedback.as_deref(), Some("up"));
        std::fs::remove_dir_all(base).ok();
    }
}

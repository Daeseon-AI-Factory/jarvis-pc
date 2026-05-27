use async_trait::async_trait;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

// CLAUDE.md mandates this stays a const so a model swap is one-line.
pub const VISION_MODEL: &str = "claude-sonnet-4-6";
#[allow(dead_code)]
pub const TEXT_MODEL: &str = "claude-haiku-4-5-20251001";

const ANTHROPIC_API_URL: &str = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION: &str = "2023-06-01";
const DEFAULT_MAX_TOKENS: u32 = 1024;

/// Structured output the trigger panel / overlay actually renders.
/// All fields are optional because the model occasionally returns malformed
/// JSON — callers fall back to `raw` in that case.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AnalysisResult {
    pub screen_state: Option<String>,
    pub next_action: Option<String>,
    pub coordinates: Option<[i32; 4]>,
    pub reasoning: Option<String>,
    /// Raw model output, before JSON parsing. Always populated.
    pub raw: String,
    /// Filled in by lib::analyze after sessions::save_session — None when
    /// persistence failed or the dispatcher was called directly from tests.
    #[serde(default)]
    pub session_dir: Option<String>,
}

#[derive(Debug)]
pub enum DispatchError {
    MissingApiKey,
    Network(String),
    Parse(String),
    Auth(String),
    Api { status: u16, body: String },
    Other(String),
}

impl std::fmt::Display for DispatchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingApiKey => write!(f, "ANTHROPIC_API_KEY not set"),
            Self::Network(e) => write!(f, "network: {e}"),
            Self::Parse(e) => write!(f, "parse: {e}"),
            Self::Auth(e) => write!(f, "auth: {e}"),
            Self::Api { status, body } => write!(f, "api {status}: {body}"),
            Self::Other(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for DispatchError {}

/// Single seam every Phase >= 2.3 calls through. Future swap-in for a local
/// vision model only has to satisfy this trait.
#[async_trait]
pub trait LLMDispatcher: Send + Sync {
    async fn analyze(
        &self,
        image_bytes: Vec<u8>,
        instruction: String,
    ) -> Result<AnalysisResult, DispatchError>;
}

pub struct AnthropicDispatcher {
    client: Client,
    api_key: String,
    model: String,
    max_tokens: u32,
}

impl AnthropicDispatcher {
    /// Errors with MissingApiKey instead of panicking — SPEC R5 says the
    /// build keeps working even when the key isn't ready yet; the failure
    /// surfaces only at the moment a caller asks for the dispatcher.
    pub fn new() -> Result<Self, DispatchError> {
        let api_key = crate::anthropic_api_key().ok_or(DispatchError::MissingApiKey)?;
        let client = Client::builder()
            .build()
            .map_err(|e| DispatchError::Other(format!("reqwest client: {e}")))?;
        Ok(Self {
            client,
            api_key,
            model: VISION_MODEL.to_string(),
            max_tokens: DEFAULT_MAX_TOKENS,
        })
    }

    pub fn with_model(mut self, m: impl Into<String>) -> Self {
        self.model = m.into();
        self
    }

    pub fn model(&self) -> &str {
        &self.model
    }
}

#[async_trait]
impl LLMDispatcher for AnthropicDispatcher {
    async fn analyze(
        &self,
        image_bytes: Vec<u8>,
        instruction: String,
    ) -> Result<AnalysisResult, DispatchError> {
        let b64 = BASE64_STANDARD.encode(&image_bytes);
        let body = json!({
            "model": self.model,
            "max_tokens": self.max_tokens,
            "system": crate::prompts::SYSTEM_PROMPT,
            "messages": [{
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/png",
                            "data": b64,
                        }
                    },
                    {
                        "type": "text",
                        "text": crate::prompts::user_text(&instruction),
                    }
                ]
            }]
        });

        tracing::info!(
            target: "dispatcher",
            "analyze begin: model={}, image_bytes={}, instr_len={}",
            self.model,
            image_bytes.len(),
            instruction.len()
        );

        let resp = self
            .client
            .post(ANTHROPIC_API_URL)
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| DispatchError::Network(e.to_string()))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| DispatchError::Network(e.to_string()))?;

        if !status.is_success() {
            tracing::warn!(
                target: "dispatcher",
                "analyze fail: status={}, body_len={}",
                status.as_u16(),
                text.len()
            );
            return Err(match status.as_u16() {
                401 | 403 => DispatchError::Auth(text),
                code => DispatchError::Api { status: code, body: text },
            });
        }

        let envelope: Value = serde_json::from_str(&text)
            .map_err(|e| DispatchError::Parse(format!("envelope: {e}; body[..200]={}", &text.chars().take(200).collect::<String>())))?;

        let raw = envelope
            .get("content")
            .and_then(|c| c.as_array())
            .and_then(|arr| arr.iter().find_map(|m| {
                if m.get("type").and_then(|t| t.as_str()) == Some("text") {
                    m.get("text").and_then(|t| t.as_str()).map(str::to_string)
                } else {
                    None
                }
            }))
            .unwrap_or_default();

        tracing::info!(
            target: "dispatcher",
            "analyze ok: status={}, raw_len={}",
            status.as_u16(),
            raw.len()
        );

        Ok(parse_analysis(raw))
    }
}

/// Free-via-subscription alternative to AnthropicDispatcher: shells out to the
/// `claude` CLI (Claude Code) in --print mode. Reuses the user's Pro/Max
/// subscription so no API key is needed; ANTHROPIC_API_KEY is explicitly
/// unset before spawn so a stale key in the shell env doesn't override the
/// subscription credential.
pub struct ClaudeCliDispatcher {
    binary: String,
    model: String,
}

impl ClaudeCliDispatcher {
    pub fn new() -> Self {
        Self {
            binary: "claude".to_string(),
            model: VISION_MODEL.to_string(),
        }
    }

    pub fn with_binary(mut self, b: impl Into<String>) -> Self {
        self.binary = b.into();
        self
    }
}

#[async_trait]
impl LLMDispatcher for ClaudeCliDispatcher {
    async fn analyze(
        &self,
        image_bytes: Vec<u8>,
        instruction: String,
    ) -> Result<AnalysisResult, DispatchError> {
        // 1. Drop the PNG to a temp file. claude's Read tool wants a real
        //    filesystem path — there's no inline base64 path on the CLI.
        let temp_dir = std::env::temp_dir();
        let temp_name = format!("sb-{}.png", uuid::Uuid::new_v4());
        let temp_path = temp_dir.join(&temp_name);
        tokio::fs::write(&temp_path, &image_bytes)
            .await
            .map_err(|e| DispatchError::Other(format!("temp png write: {e}")))?;

        let temp_path_str = temp_path.to_string_lossy().to_string();
        let prompt = format!(
            "다음 화면 캡처 이미지를 Read 도구로 읽고, 그 아래에 적힌 AI 지시를 현재 사용자 화면에 맞게 번역해서 JSON으로 응답해.\n\n이미지: {}\n\nAI 지시:\n{}",
            temp_path_str,
            instruction.trim()
        );

        tracing::info!(
            target: "dispatcher",
            "claude-cli analyze begin: image_bytes={}, instr_len={}, model={}",
            image_bytes.len(),
            instruction.len(),
            self.model
        );

        let allow_dir = temp_dir.to_string_lossy().to_string();
        let result = tokio::process::Command::new(&self.binary)
            // The shell's ANTHROPIC_API_KEY (which is currently invalid)
            // would otherwise force claude into API-key mode and 401.
            .env_remove("ANTHROPIC_API_KEY")
            .arg("--print")
            .arg("--model").arg(&self.model)
            .arg("--output-format").arg("text")
            .arg("--system-prompt").arg(crate::prompts::SYSTEM_PROMPT)
            .arg("--add-dir").arg(&allow_dir)
            .arg("--allowed-tools").arg("Read")
            .arg("--dangerously-skip-permissions")
            .arg(&prompt)
            .output()
            .await;

        let _ = tokio::fs::remove_file(&temp_path).await;

        let output = result.map_err(|e| DispatchError::Other(format!("claude spawn: {e}")))?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
            let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
            return Err(DispatchError::Other(format!(
                "claude exit {:?}; stderr={}; stdout={}",
                output.status.code(),
                stderr.chars().take(400).collect::<String>(),
                stdout.chars().take(400).collect::<String>()
            )));
        }
        let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
        tracing::info!(
            target: "dispatcher",
            "claude-cli analyze ok: raw_len={}",
            raw.len()
        );
        Ok(parse_analysis(raw))
    }
}

/// Groq + Llama 3.2 11B Vision (or whatever vision model Groq currently
/// hosts free). OpenAI-compatible API. Free tier 30 RPM / 1000 RPD / 6K TPM
/// is plenty for dogfooding.
pub struct GroqDispatcher {
    client: Client,
    api_key: String,
    model: String,
}

const GROQ_API_URL: &str = "https://api.groq.com/openai/v1/chat/completions";
/// 2026-05-27 console.groq.com/docs/vision 확인: 현재 vision 모델은 이거 하나.
/// Preview 상태. 128K context, max 5 images, base64 4MB 한도. 우리 다운스케일
/// 후 ~1MB PNG라 OK. 모델 lineup 바뀌면 vision docs 재확인.
pub const GROQ_VISION_MODEL: &str = "meta-llama/llama-4-scout-17b-16e-instruct";

impl GroqDispatcher {
    pub fn new() -> Result<Self, DispatchError> {
        let api_key = crate::groq_api_key().ok_or(DispatchError::MissingApiKey)?;
        let client = Client::builder()
            .build()
            .map_err(|e| DispatchError::Other(format!("reqwest client: {e}")))?;
        Ok(Self {
            client,
            api_key,
            model: GROQ_VISION_MODEL.to_string(),
        })
    }

    pub fn with_model(mut self, m: impl Into<String>) -> Self {
        self.model = m.into();
        self
    }
}

#[async_trait]
impl LLMDispatcher for GroqDispatcher {
    async fn analyze(
        &self,
        image_bytes: Vec<u8>,
        instruction: String,
    ) -> Result<AnalysisResult, DispatchError> {
        let b64 = BASE64_STANDARD.encode(&image_bytes);
        let body = json!({
            "model": self.model,
            "max_tokens": DEFAULT_MAX_TOKENS,
            "temperature": 0.0,
            "messages": [
                {
                    "role": "system",
                    "content": crate::prompts::SYSTEM_PROMPT,
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": crate::prompts::user_text(&instruction),
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": format!("data:image/png;base64,{b64}"),
                            },
                        }
                    ]
                }
            ]
        });

        tracing::info!(
            target: "dispatcher",
            "groq analyze begin: model={}, image_bytes={}, instr_len={}",
            self.model,
            image_bytes.len(),
            instruction.len()
        );

        let resp = self
            .client
            .post(GROQ_API_URL)
            .bearer_auth(&self.api_key)
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| DispatchError::Network(e.to_string()))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| DispatchError::Network(e.to_string()))?;

        if !status.is_success() {
            return Err(match status.as_u16() {
                401 | 403 => DispatchError::Auth(text),
                code => DispatchError::Api {
                    status: code,
                    body: text.chars().take(800).collect(),
                },
            });
        }

        let envelope: Value = serde_json::from_str(&text).map_err(|e| {
            DispatchError::Parse(format!(
                "groq envelope: {e}; body[..200]={}",
                text.chars().take(200).collect::<String>()
            ))
        })?;

        let raw = envelope
            .get("choices")
            .and_then(|c| c.as_array())
            .and_then(|arr| arr.first())
            .and_then(|m| m.get("message"))
            .and_then(|m| m.get("content"))
            .and_then(|c| c.as_str())
            .unwrap_or_default()
            .to_string();

        tracing::info!(
            target: "dispatcher",
            "groq analyze ok: raw_len={}",
            raw.len()
        );
        Ok(parse_analysis(raw))
    }
}

/// Google Gemini API. Native multimodal. Free tier 250-1000 RPD depending on
/// model. URL uses ?key=<token> query param (not Bearer).
pub struct GeminiDispatcher {
    client: Client,
    api_key: String,
    model: String,
}

const GEMINI_API_BASE: &str = "https://generativelanguage.googleapis.com/v1beta/models";
pub const GEMINI_VISION_MODEL: &str = "gemini-2.5-flash";

impl GeminiDispatcher {
    pub fn new() -> Result<Self, DispatchError> {
        let api_key = crate::gemini_api_key().ok_or(DispatchError::MissingApiKey)?;
        let client = Client::builder()
            .build()
            .map_err(|e| DispatchError::Other(format!("reqwest client: {e}")))?;
        Ok(Self {
            client,
            api_key,
            model: GEMINI_VISION_MODEL.to_string(),
        })
    }

    pub fn with_model(mut self, m: impl Into<String>) -> Self {
        self.model = m.into();
        self
    }
}

#[async_trait]
impl LLMDispatcher for GeminiDispatcher {
    async fn analyze(
        &self,
        image_bytes: Vec<u8>,
        instruction: String,
    ) -> Result<AnalysisResult, DispatchError> {
        let b64 = BASE64_STANDARD.encode(&image_bytes);
        let body = json!({
            "system_instruction": {
                "parts": [{"text": crate::prompts::SYSTEM_PROMPT}]
            },
            "contents": [
                {
                    "parts": [
                        {"text": crate::prompts::user_text(&instruction)},
                        {
                            "inline_data": {
                                "mime_type": "image/png",
                                "data": b64
                            }
                        }
                    ]
                }
            ],
            "generationConfig": {
                "maxOutputTokens": DEFAULT_MAX_TOKENS,
                "temperature": 0.0
            }
        });

        let url = format!(
            "{}/{}:generateContent?key={}",
            GEMINI_API_BASE, self.model, self.api_key
        );

        tracing::info!(
            target: "dispatcher",
            "gemini analyze begin: model={}, image_bytes={}, instr_len={}",
            self.model,
            image_bytes.len(),
            instruction.len()
        );

        let resp = self
            .client
            .post(&url)
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| DispatchError::Network(e.to_string()))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| DispatchError::Network(e.to_string()))?;

        if !status.is_success() {
            return Err(match status.as_u16() {
                401 | 403 => DispatchError::Auth(text),
                code => DispatchError::Api {
                    status: code,
                    body: text.chars().take(800).collect(),
                },
            });
        }

        let envelope: Value = serde_json::from_str(&text).map_err(|e| {
            DispatchError::Parse(format!(
                "gemini envelope: {e}; body[..200]={}",
                text.chars().take(200).collect::<String>()
            ))
        })?;

        let raw = envelope
            .get("candidates")
            .and_then(|c| c.as_array())
            .and_then(|arr| arr.first())
            .and_then(|m| m.get("content"))
            .and_then(|c| c.get("parts"))
            .and_then(|p| p.as_array())
            .and_then(|arr| arr.iter().find_map(|p| p.get("text").and_then(|t| t.as_str())))
            .unwrap_or_default()
            .to_string();

        tracing::info!(
            target: "dispatcher",
            "gemini analyze ok: raw_len={}",
            raw.len()
        );
        Ok(parse_analysis(raw))
    }
}

fn strip_code_fences(s: &str) -> String {
    let s = s.trim();
    let body = s
        .strip_prefix("```json")
        .or_else(|| s.strip_prefix("```JSON"))
        .or_else(|| s.strip_prefix("```"));
    if let Some(rest) = body {
        let rest = rest.trim_start_matches('\n');
        if let Some(end) = rest.rfind("```") {
            return rest[..end].trim().to_string();
        }
    }
    s.to_string()
}

/// Parse model raw output into the structured AnalysisResult. Tolerates
/// markdown code fences and missing fields — anything we can't extract just
/// stays None and callers fall back to `raw`.
pub fn parse_analysis(raw: String) -> AnalysisResult {
    let mut out = AnalysisResult {
        raw: raw.clone(),
        ..Default::default()
    };
    let cleaned = strip_code_fences(&raw);
    let Ok(value) = serde_json::from_str::<Value>(&cleaned) else {
        return out;
    };
    out.screen_state = value
        .get("screen_state")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    out.next_action = value
        .get("next_action")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    out.reasoning = value
        .get("reasoning")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    if let Some(arr) = value.get("coordinates").and_then(|v| v.as_array()) {
        if arr.len() == 4 {
            let parts: Option<Vec<i32>> = arr
                .iter()
                .map(|v| v.as_i64().map(|n| n as i32))
                .collect();
            if let Some(p) = parts {
                out.coordinates = Some([p[0], p[1], p[2], p[3]]);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_well_formed_json() {
        let raw = r#"{
            "screen_state": "vercel dashboard, no project yet",
            "next_action": "우측 상단 'New Project' 버튼 클릭",
            "coordinates": [1200, 80, 120, 36],
            "reasoning": "사이드바 아래에 항목 없음"
        }"#;
        let r = parse_analysis(raw.to_string());
        assert_eq!(r.screen_state.as_deref(), Some("vercel dashboard, no project yet"));
        assert_eq!(r.coordinates, Some([1200, 80, 120, 36]));
        assert!(r.next_action.is_some());
        assert!(r.reasoning.is_some());
        assert_eq!(r.raw, raw);
    }

    #[test]
    fn parse_strips_markdown_fences() {
        let raw = "```json\n{\"screen_state\":\"x\",\"next_action\":\"y\",\"coordinates\":null,\"reasoning\":\"z\"}\n```";
        let r = parse_analysis(raw.to_string());
        assert_eq!(r.screen_state.as_deref(), Some("x"));
        assert_eq!(r.next_action.as_deref(), Some("y"));
        assert_eq!(r.coordinates, None);
    }

    #[test]
    fn parse_falls_back_to_raw_on_garbage() {
        let raw = "not json at all";
        let r = parse_analysis(raw.to_string());
        assert!(r.screen_state.is_none());
        assert!(r.next_action.is_none());
        assert!(r.coordinates.is_none());
        assert_eq!(r.raw, raw);
    }

    #[test]
    fn parse_keeps_partial_fields() {
        let raw = r#"{"screen_state":"ok","coordinates":[10,20,30,40]}"#;
        let r = parse_analysis(raw.to_string());
        assert_eq!(r.screen_state.as_deref(), Some("ok"));
        assert_eq!(r.coordinates, Some([10, 20, 30, 40]));
        assert!(r.next_action.is_none());
    }
}

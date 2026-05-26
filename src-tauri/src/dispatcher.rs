use async_trait::async_trait;
use serde::{Deserialize, Serialize};

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

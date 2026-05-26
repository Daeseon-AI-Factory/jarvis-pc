use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
pub struct Fixture {
    pub image_path: PathBuf,
    pub ai_instruction: String,
    pub expected_keywords: Vec<String>,
}

#[derive(Debug)]
pub enum FixtureError {
    Io(std::io::Error),
    Parse(serde_json::Error),
}

impl std::fmt::Display for FixtureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(e) => write!(f, "fixtures io: {e}"),
            Self::Parse(e) => write!(f, "fixtures parse: {e}"),
        }
    }
}

impl std::error::Error for FixtureError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(e) => Some(e),
            Self::Parse(e) => Some(e),
        }
    }
}

impl From<std::io::Error> for FixtureError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<serde_json::Error> for FixtureError {
    fn from(e: serde_json::Error) -> Self {
        Self::Parse(e)
    }
}

pub fn fixtures_dir() -> PathBuf {
    crate::project_root().join("fixtures")
}

pub fn load_fixtures() -> Result<Vec<Fixture>, FixtureError> {
    let json_path = fixtures_dir().join("instructions.json");
    let text = std::fs::read_to_string(&json_path)?;
    let fixtures: Vec<Fixture> = serde_json::from_str(&text)?;
    Ok(fixtures)
}

impl Fixture {
    /// image_path inside instructions.json is repo-root-relative
    /// ("fixtures/foo.png"); resolve absolute so callers can ignore cwd.
    pub fn absolute_image_path(&self) -> PathBuf {
        if self.image_path.is_absolute() {
            self.image_path.clone()
        } else {
            crate::project_root().join(&self.image_path)
        }
    }
}

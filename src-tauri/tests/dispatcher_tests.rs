use screenbridge_lib::fixtures::load_fixtures;
use screenbridge_lib::{anthropic_api_key, is_api_key_available, project_root};

// Phase 1.2 verify — fixtures/instructions.json deserializes into ≥1 entry.
#[test]
fn load_fixtures_returns_at_least_one() {
    let fx = load_fixtures().expect("load_fixtures should succeed");
    assert!(
        !fx.is_empty(),
        "fixtures/instructions.json must contain at least one entry"
    );
    for f in &fx {
        assert!(!f.ai_instruction.trim().is_empty(), "ai_instruction empty");
        assert!(
            !f.expected_keywords.is_empty(),
            "expected_keywords empty for {:?}",
            f.image_path
        );
    }
}

// Phase 1.3 verify — when no real key is reachable from any source the helper
// reports unavailable. Skips itself the moment either process env or .env
// carries a plausible key.
#[test]
fn placeholder_env_reports_unavailable() {
    if std::env::var("ANTHROPIC_API_KEY")
        .ok()
        .map(|v| !v.is_empty() && v != "placeholder" && !v.contains("YOUR"))
        .unwrap_or(false)
    {
        eprintln!(
            "skip: process env has a non-placeholder ANTHROPIC_API_KEY \
             (key picked up by anthropic_api_key())"
        );
        return;
    }
    let env_path = project_root().join(".env");
    let text = std::fs::read_to_string(&env_path).unwrap_or_default();
    if !text.contains("ANTHROPIC_API_KEY") {
        eprintln!("skip: .env has no ANTHROPIC_API_KEY line");
        return;
    }
    if !text.contains("placeholder") || text.contains("sk-ant-") {
        eprintln!("skip: .env no longer looks like the placeholder state");
        return;
    }
    assert!(
        !is_api_key_available(),
        "placeholder-only state should report key unavailable"
    );
    assert!(anthropic_api_key().is_none(), "key should be None");
}

// Phase 2.4 stub — full analyze() loop. Wired in Phase 2.4 once the
// AnthropicDispatcher exists and gates on is_api_key_available().

use screenbridge_lib::fixtures::load_fixtures;

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

// Phase 2.4 stub — full analyze() loop. Wired in Phase 2.4 once the
// AnthropicDispatcher exists and is_api_key_available() lives in config.

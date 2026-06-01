//
//  PromptsTests.swift
//  ScreenBridgeTests — Phase 2.2
//

import Testing
@testable import ScreenBridge

@Suite("Prompts")
struct PromptsTests {

    @Test("systemPrompt에 5개 schema 키 모두 포함 (AnalysisResult와 1:1)")
    func systemPromptContainsAllSchemaKeys() {
        let p = Prompts.systemPrompt
        #expect(p.contains("screen_state"))
        #expect(p.contains("next_action"))
        #expect(p.contains("target_text"))
        #expect(p.contains("coordinates"))
        #expect(p.contains("reasoning"))
    }

    @Test("systemPrompt에 ✗/✓ 페어 + 비-AI-native 친화 톤 예시 포함 (Layer 16 학습 직역)")
    func systemPromptContainsExamples() {
        let p = Prompts.systemPrompt
        #expect(p.contains("✗"))
        #expect(p.contains("✓"))
        #expect(p.contains("Sign in"))                  // visible text 예시
        #expect(p.contains("Create API Key"))            // 한·영 혼합 예시
        #expect(p.contains("환경 변수 추가"))             // 한국어 visible text 예시
        #expect(p.contains("여기 [Settings]"))           // 친화 톤 예시
    }

    @Test("systemPrompt에 본질 룰 키워드 포함")
    func systemPromptContainsCoreRules() {
        let p = Prompts.systemPrompt
        #expect(p.contains("한국어"))
        #expect(p.contains("JSON"))
        #expect(p.contains("번역기"))
        #expect(p.contains("한 동작"))            // 한 화면 = 한 동작
        #expect(p.contains("AI가 시킨 게 정확히 뭔지 처 모르는 사람"))  // 타겟 명시
    }

    @Test("systemPrompt는 7KB 미만 (Gemini token budget 부담 최소)")
    func systemPromptIsReasonablyShort() {
        // Phase 9.0 갱신: 5000 → 7000. Phase 7.0 (continuation + target_role + irreversible)
        // + Phase 9.0 (간결 룰 + 스크롤 안내) clause 박힌 후 5869 byte. 7000 안.
        #expect(Prompts.systemPrompt.count < 7000)
    }
}

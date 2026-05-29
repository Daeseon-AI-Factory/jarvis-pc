//
//  AnalysisResult.swift
//  ScreenBridge — Phase 2.1
//
//  LLM dispatcher의 응답 contract.
//
//  본질 (product-identity-screenbridge):
//  - `targetText`는 visible text 그대로. OCR + ElementMatcher의 deterministic source.
//    LLM에게 픽셀 좌표 추정시키지 않는다 (그건 ~70%, 본질 "99%"에 못 맞음).
//  - `coordinates`는 fallback only — LLM이 채울 수도 있고 안 채울 수도. OCR 매칭
//    성공 시 무시. 평소값은 nil.
//  - `nextAction`은 HUD bubble용 한국어 한 문장. 비-AI-native 친화 톤
//    ("여기 [Sign in] 버튼 누르세요").
//  - `raw`는 LLM raw 응답 전체 — Codable에서 분리. dispatcher가 `withRaw(_:)`로 후채움.
//

import Foundation

struct AnalysisResult: Codable, Sendable, Equatable {
    let screenState: String
    let nextAction: String
    let targetText: String
    let coordinates: [Int]?
    let reasoning: String
    let raw: String

    init(
        screenState: String,
        nextAction: String,
        targetText: String,
        coordinates: [Int]? = nil,
        reasoning: String,
        raw: String = ""
    ) {
        self.screenState = screenState
        self.nextAction = nextAction
        self.targetText = targetText
        self.coordinates = coordinates
        self.reasoning = reasoning
        self.raw = raw
    }

    private enum CodingKeys: String, CodingKey {
        case screenState = "screen_state"
        case nextAction = "next_action"
        case targetText = "target_text"
        case coordinates
        case reasoning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            screenState: try c.decode(String.self, forKey: .screenState),
            nextAction: try c.decode(String.self, forKey: .nextAction),
            targetText: try c.decode(String.self, forKey: .targetText),
            coordinates: try c.decodeIfPresent([Int].self, forKey: .coordinates),
            reasoning: try c.decode(String.self, forKey: .reasoning),
            raw: ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(screenState, forKey: .screenState)
        try c.encode(nextAction, forKey: .nextAction)
        try c.encode(targetText, forKey: .targetText)
        try c.encodeIfPresent(coordinates, forKey: .coordinates)
        try c.encode(reasoning, forKey: .reasoning)
    }

    func withRaw(_ raw: String) -> AnalysisResult {
        AnalysisResult(
            screenState: screenState,
            nextAction: nextAction,
            targetText: targetText,
            coordinates: coordinates,
            reasoning: reasoning,
            raw: raw
        )
    }
}

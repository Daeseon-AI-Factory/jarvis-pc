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
    let targetRole: String?       // AX role hint (Phase 5.x multi-target ambiguity 차단)
    let coordinates: [Int]?
    let reasoning: String
    let raw: String
    // Phase 7.0: continuation 필드. default 값으로 v0.1 single-shot 동작 보존.
    let taskComplete: Bool        // true = task 끝, HUD presentCompletion pill. v0.1는 무시.
    let requiresConfirmation: Bool // true = 되돌릴 수 없는 동작, HUD 빨강 border + 경고.
    let stepActionSummary: String? // ≤30 words, *다음* call의 previousSteps에 박을 거.

    init(
        screenState: String,
        nextAction: String,
        targetText: String,
        targetRole: String? = nil,
        coordinates: [Int]? = nil,
        reasoning: String,
        raw: String = "",
        taskComplete: Bool = false,
        requiresConfirmation: Bool = false,
        stepActionSummary: String? = nil
    ) {
        self.screenState = screenState
        self.nextAction = nextAction
        self.targetText = targetText
        self.targetRole = targetRole
        self.coordinates = coordinates
        self.reasoning = reasoning
        self.raw = raw
        self.taskComplete = taskComplete
        self.requiresConfirmation = requiresConfirmation
        self.stepActionSummary = stepActionSummary
    }

    private enum CodingKeys: String, CodingKey {
        case screenState = "screen_state"
        case nextAction = "next_action"
        case targetText = "target_text"
        case targetRole = "target_role"
        case coordinates
        case reasoning
        case taskComplete = "task_complete"
        case requiresConfirmation = "requires_confirmation"
        case stepActionSummary = "step_action_summary"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            screenState: try c.decode(String.self, forKey: .screenState),
            nextAction: try c.decode(String.self, forKey: .nextAction),
            targetText: try c.decode(String.self, forKey: .targetText),
            targetRole: try c.decodeIfPresent(String.self, forKey: .targetRole),
            coordinates: try c.decodeIfPresent([Int].self, forKey: .coordinates),
            reasoning: try c.decode(String.self, forKey: .reasoning),
            raw: "",
            taskComplete: (try? c.decode(Bool.self, forKey: .taskComplete)) ?? false,
            requiresConfirmation: (try? c.decode(Bool.self, forKey: .requiresConfirmation)) ?? false,
            stepActionSummary: try? c.decodeIfPresent(String.self, forKey: .stepActionSummary)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(screenState, forKey: .screenState)
        try c.encode(nextAction, forKey: .nextAction)
        try c.encode(targetText, forKey: .targetText)
        try c.encodeIfPresent(targetRole, forKey: .targetRole)
        try c.encodeIfPresent(coordinates, forKey: .coordinates)
        try c.encode(reasoning, forKey: .reasoning)
        try c.encode(taskComplete, forKey: .taskComplete)
        try c.encode(requiresConfirmation, forKey: .requiresConfirmation)
        try c.encodeIfPresent(stepActionSummary, forKey: .stepActionSummary)
    }

    func withRaw(_ raw: String) -> AnalysisResult {
        AnalysisResult(
            screenState: screenState,
            nextAction: nextAction,
            targetText: targetText,
            targetRole: targetRole,
            coordinates: coordinates,
            reasoning: reasoning,
            raw: raw,
            taskComplete: taskComplete,
            requiresConfirmation: requiresConfirmation,
            stepActionSummary: stepActionSummary
        )
    }
}

// Phase 7.0: 되돌릴 수 없는 동작 keyword post-filter.
// LLM이 requires_confirmation 빼먹어도 *backend가 강제 true* — 2-layer safety gate.
// "이체하기" / "확정" / "확인" 같은 Korean 변형 적극 추가 — synthesis risk #3.
enum IrreversibleActions {
    static let keywords: [String] = [
        // 한국어 — 금융/메시지/삭제
        "송금", "이체", "결제", "결재", "지불", "보내기", "전송", "삭제", "지우기",
        "확정", "확인", "동의", "구매", "주문", "예약", "취소", "탈퇴", "로그아웃",
        // 영어
        "send", "delete", "remove", "transfer", "pay", "purchase", "buy", "confirm",
        "submit", "publish", "post", "cancel", "unsubscribe", "sign out", "logout",
        "agree", "accept",
    ]

    /// next_action 또는 target_text에 위험 keyword 있으면 true. LLM 응답과 OR 통합.
    static func isIrreversible(nextAction: String, targetText: String) -> Bool {
        let blob = (nextAction + " " + targetText).lowercased()
        return keywords.contains { blob.contains($0.lowercased()) }
    }
}

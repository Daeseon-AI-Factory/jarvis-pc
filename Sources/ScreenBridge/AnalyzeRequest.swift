//
//  AnalyzeRequest.swift
//  ScreenBridge — Phase 4.2
//
//  Analyze 1회 요청 + 진행 stage.
//

import CoreGraphics
import Foundation

struct AnalyzeRequest: Sendable {
    let instruction: String
    let triggeredAt: Date
    // Phase 7.0: continuation context. nil = single-shot (v0.1 동작 그대로).
    let sessionID: String?
    let previousSteps: [StepSummary]?

    init(
        instruction: String,
        triggeredAt: Date,
        sessionID: String? = nil,
        previousSteps: [StepSummary]? = nil
    ) {
        self.instruction = instruction
        self.triggeredAt = triggeredAt
        self.sessionID = sessionID
        self.previousSteps = previousSteps
    }
}

/// 이전 step의 *결과* 요약. LLM이 자기 자신 응답으로 next call에 자기 history 박음
/// (≤30 words). full screenshot history 박는 거 X — token quadratic 방지 (Phase 7.0 design).
struct StepSummary: Sendable, Codable, Equatable {
    let stepNumber: Int
    let actionTaken: String   // ≤30 words, LLM-authored on prior call
}

/// Analyze 진행 stage. Phase 5.x에서 AsyncStream으로 progressive UI 가능.
/// `matched`는 OCR/AX matcher 결과 (rect + matchedText + sourceTag).
/// 없으면 caller가 `result.coordinates` LLM 추정 fallback 또는 bubble만.
enum AnalyzeStage: Sendable {
    case capturing
    case analyzing(elapsed: TimeInterval)
    /// `matches`: top N (max 2) distinct candidates. `matches[0]` = primary (빨강),
    /// `matches[1]` (있으면) = alternative (회색 dashed + 2번 라벨).
    /// 빈 배열이면 caller가 LLM coords fallback 또는 에러.
    case done(result: AnalysisResult, geometry: DisplayGeometry, matches: [MatchResult])
    case failed(DispatcherError)
}

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
}

/// Analyze 진행 stage. Phase 5.x에서 AsyncStream으로 progressive UI 가능.
/// `matchedRect`는 OCR + ElementMatcher가 deterministic 매칭한 결과 (있으면).
/// 없으면 caller가 `result.coordinates` LLM 추정 fallback 또는 bubble만.
enum AnalyzeStage: Sendable {
    case capturing
    case analyzing(elapsed: TimeInterval)
    case done(result: AnalysisResult, geometry: DisplayGeometry, matchedRect: CGRect?)
    case failed(DispatcherError)
}

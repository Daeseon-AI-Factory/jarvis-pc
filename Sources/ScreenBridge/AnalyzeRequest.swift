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
/// Phase 4.2는 단일 await — `.done` 또는 `.failed`만 반환.
enum AnalyzeStage: Sendable {
    case capturing
    case analyzing(elapsed: TimeInterval)
    case done(result: AnalysisResult, geometry: DisplayGeometry)
    case failed(DispatcherError)
}

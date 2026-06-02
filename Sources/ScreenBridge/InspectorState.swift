//
//  InspectorState.swift
//  ScreenBridge — v0.3 Session Inspector (사용자 요청 2026-06-02)
//
//  AnalyzeCoordinator (actor)의 session 진행 상황을 MainActor publish.
//  SessionInspectorPanel (별도 NSPanel)이 SwiftUI ObservableObject 구독.
//
//  목적:
//  - 자녀가 어머님 옆에서 *진행 상황* 봄 (멀리서 도움)
//  - 기업 compliance audit (사용자가 *어떤 step* 박혔는지)
//  - 사용자 본인 디버그 (Qwen tokens/sec, Gemini latency, irreversible badge)
//  - Privacy mode 명확 표시 (cloud / local / blocked)
//

import Foundation
import SwiftUI

/// Single source of truth for Session Inspector. MainActor 박힘.
@MainActor
final class InspectorState: ObservableObject {

    /// Process-wide singleton.
    static let shared = InspectorState()

    enum Phase: Sendable, Equatable {
        case idle
        case analyzing(stepIndex: Int)
        case waitingForUserClick(stepIndex: Int)
        case completed
        case cancelled
        case failed(String)
    }

    /// Step view-model — Step별 한 줄 표시.
    struct StepView: Identifiable, Equatable {
        let id = UUID()
        let stepNumber: Int
        let targetText: String
        let nextAction: String
        let sourceTag: String         // AX:AXDockItem / OCR / LLM-fallback / Qwen
        let irreversible: Bool        // 빨강 경고 badge
        let elapsedSec: Double
        let timestamp: Date
    }

    @Published var sessionID: String?
    @Published var instruction: String?
    @Published var steps: [StepView] = []
    @Published var phase: Phase = .idle

    /// 현재 사용 중인 dispatcher name. "gemini" / "claude" / "qwen-local" / "fallback".
    @Published var dispatcherName: String = "?"

    /// Router 결정. cloud / localOnly / blocked.
    @Published var privacyMode: String = "cloud"

    /// 마지막 step elapsed (sec).
    @Published var lastElapsed: Double?

    /// 마지막 Qwen tokens/sec — Phase 9 박은 거. Gemini/Claude는 nil.
    @Published var lastTokensPerSecond: Double?

    private init() {}

    // MARK: - Lifecycle (AnalyzeCoordinator → MainActor wire)

    func beginSession(id: String, instruction: String, dispatcherName: String, privacyMode: String) {
        self.sessionID = id
        self.instruction = instruction
        self.steps = []
        self.phase = .analyzing(stepIndex: 0)
        self.dispatcherName = dispatcherName
        self.privacyMode = privacyMode
        self.lastElapsed = nil
        self.lastTokensPerSecond = nil
    }

    func appendStep(_ step: StepView) {
        steps.append(step)
        lastElapsed = step.elapsedSec
        phase = .waitingForUserClick(stepIndex: step.stepNumber)
    }

    func markAnalyzing(stepIndex: Int) {
        phase = .analyzing(stepIndex: stepIndex)
    }

    func finishCompleted() {
        phase = .completed
    }

    func finishCancelled() {
        phase = .cancelled
    }

    func finishFailed(_ reason: String) {
        phase = .failed(reason)
    }

    /// 다음 session 시작 또는 panel 닫음 전 — *초기화 X*. 이전 session 봄.
    /// idle 복귀는 *새 session begin* 시점만.
}

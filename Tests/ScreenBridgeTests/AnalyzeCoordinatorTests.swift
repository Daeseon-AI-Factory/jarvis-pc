//
//  AnalyzeCoordinatorTests.swift
//  ScreenBridgeTests — Phase 4.2
//

import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import ScreenBridge

@Suite("AnalyzeCoordinator")
struct AnalyzeCoordinatorTests {

    // MARK: - Mocks

    struct MockCapture: ScreenCaptureService {
        let data: Data
        let geometry: DisplayGeometry

        func captureCursorScreen() async throws -> (Data, DisplayGeometry) {
            (data, geometry)
        }
    }

    actor MockDispatcher: LLMDispatcher {
        nonisolated let mockResult: AnalysisResult

        init(result: AnalysisResult) {
            self.mockResult = result
        }

        func analyze(imageData: Data, imageSize: CGSize, instruction: String) async throws -> AnalysisResult {
            mockResult
        }
    }

    struct ThrowingDispatcher: LLMDispatcher {
        let error: DispatcherError

        func analyze(imageData: Data, imageSize: CGSize, instruction: String) async throws -> AnalysisResult {
            throw error
        }
    }

    struct ThrowingCapture: ScreenCaptureService {
        let error: ScreenCapture.CaptureError

        func captureCursorScreen() async throws -> (Data, DisplayGeometry) {
            throw error
        }
    }

    // MARK: - Fixtures

    private func mockGeometry() -> DisplayGeometry {
        DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1024, height: 768),
            backingScaleFactor: 1.0,
            physicalSize: CGSize(width: 1024, height: 768),
            sentSize: CGSize(width: 1024, height: 768)
        )
    }

    private func mockResult() -> AnalysisResult {
        AnalysisResult(
            screenState: "test screen",
            nextAction: "여기 [Save] 누르세요",
            targetText: "Save",
            coordinates: [10, 20, 100, 30],
            reasoning: "save",
            raw: ""
        )
    }

    // MARK: - Tests

    @Test("run — capture + dispatcher 성공 → .done with result + geometry")
    func runHappyPath() async {
        let coord = AnalyzeCoordinator(
            capture: MockCapture(data: Data([1, 2, 3]), geometry: mockGeometry()),
            dispatcher: MockDispatcher(result: mockResult())
        )
        let stage = await coord.run(AnalyzeRequest(instruction: "test", triggeredAt: Date()))
        guard case .done(let result, let geom) = stage else {
            Issue.record("expected .done, got \(stage)")
            return
        }
        #expect(result.targetText == "Save")
        #expect(result.coordinates == [10, 20, 100, 30])
        #expect(geom.displayID == 1)
    }

    @Test("run — dispatcher throw → .failed(DispatcherError)")
    func runDispatcherFailure() async {
        let coord = AnalyzeCoordinator(
            capture: MockCapture(data: Data(), geometry: mockGeometry()),
            dispatcher: ThrowingDispatcher(error: .maxTokens)
        )
        let stage = await coord.run(AnalyzeRequest(instruction: "test", triggeredAt: Date()))
        guard case .failed(let err) = stage else {
            Issue.record("expected .failed")
            return
        }
        if case .maxTokens = err {} else {
            Issue.record("expected .maxTokens, got \(err)")
        }
    }

    @Test("run — capture permissionDenied → .failed mapped")
    func runCapturePermissionDenied() async {
        let coord = AnalyzeCoordinator(
            capture: ThrowingCapture(error: .permissionDenied),
            dispatcher: MockDispatcher(result: mockResult())
        )
        let stage = await coord.run(AnalyzeRequest(instruction: "test", triggeredAt: Date()))
        guard case .failed = stage else {
            Issue.record("expected .failed")
            return
        }
    }

    @Test("run — 두 번 동시 호출 시 두 번째는 reject")
    func runRejectsConcurrent() async {
        // Slow dispatcher — sleep으로 첫 번째가 진행 중
        actor SlowDispatcher: LLMDispatcher {
            nonisolated let result: AnalysisResult
            init(result: AnalysisResult) { self.result = result }
            func analyze(imageData: Data, imageSize: CGSize, instruction: String) async throws -> AnalysisResult {
                try await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
                return result
            }
        }
        let coord = AnalyzeCoordinator(
            capture: MockCapture(data: Data(), geometry: mockGeometry()),
            dispatcher: SlowDispatcher(result: mockResult())
        )

        // 동시 두 호출
        async let first = coord.run(AnalyzeRequest(instruction: "1", triggeredAt: Date()))
        try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05s — 첫 시작 보장
        async let second = coord.run(AnalyzeRequest(instruction: "2", triggeredAt: Date()))

        let (s1, s2) = await (first, second)
        // 첫 번째는 .done, 두 번째는 .failed(.invalidResponse("이미 분석 중"))
        if case .done = s1 {} else { Issue.record("first should be .done, got \(s1)") }
        if case .failed = s2 {} else { Issue.record("second should be .failed (reject)") }
    }
}

@Suite("UserMessage")
struct UserMessageTests {
    @Test("missingAPIKey → 한국어 + 'AI 키'")
    func missingAPIKey() {
        let msg = UserMessage.from(.missingAPIKey)
        #expect(msg.contains("AI 키"))
        #expect(msg.contains("등록"))
    }

    @Test("401 → 'AI 키가 잘못'")
    func httpStatus401() {
        let msg = UserMessage.from(.httpStatus(401, body: ""))
        #expect(msg.contains("AI 키"))
        #expect(msg.contains("잘못"))
    }

    @Test("429 → '무료 사용량'")
    func httpStatus429() {
        let msg = UserMessage.from(.httpStatus(429, body: ""))
        #expect(msg.contains("무료") || msg.contains("사용량"))
    }

    @Test("network → '인터넷 연결'")
    func network() {
        let urlErr = URLError(.notConnectedToInternet)
        let msg = UserMessage.from(.network(urlErr))
        #expect(msg.contains("인터넷"))
    }

    @Test("maxTokens → '응답이 너무 길'")
    func maxTokens() {
        let msg = UserMessage.from(.maxTokens)
        #expect(msg.contains("너무") || msg.contains("길"))
    }

    @Test("retriesExhausted → '여러 번 시도'")
    func retriesExhausted() {
        let msg = UserMessage.from(.retriesExhausted(lastStatus: 503))
        #expect(msg.contains("여러 번") || msg.contains("시도"))
    }

    @Test("decoding → 'AI 응답'")
    func decoding() {
        let msg = UserMessage.from(.decoding("..."))
        #expect(msg.contains("AI 응답"))
    }

    @Test("모든 메시지 jargon-free (영어 단어 0 — 라벨 제외)")
    func allMessagesKoreanOnly() {
        let errs: [DispatcherError] = [
            .missingAPIKey, .network(URLError(.unknown)),
            .httpStatus(500, body: ""), .decoding(""),
            .maxTokens, .invalidResponse(""),
            .retriesExhausted(lastStatus: 0),
        ]
        for err in errs {
            let msg = UserMessage.from(err)
            // jargon 한 단어로 확인 (FAIL, VNRequest, OSStatus 등)
            #expect(!msg.contains("VN"))
            #expect(!msg.contains("OSStatus"))
            #expect(!msg.contains("FAIL"))
            #expect(!msg.contains("Error"))
        }
    }
}

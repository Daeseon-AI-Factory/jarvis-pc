//
//  Phase70ScaffoldTests.swift
//  ScreenBridge — Phase 7.0
//
//  Continuation scaffold: IrreversibleActions keyword filter +
//  AnalysisResult Phase 7.0 default 호환성 + AnalyzeCoordinator SessionState.
//  Phase 7.1에서 transition 박힐 때 추가 tests.
//

import CoreGraphics
import Foundation
import Testing
@testable import ScreenBridge

@Suite("Phase 7.0 — IrreversibleActions keyword filter")
struct IrreversibleActionsTests {

    @Test("한국어 금융 keyword — 송금/이체/결제")
    func koreanFinancial() {
        #expect(IrreversibleActions.isIrreversible(nextAction: "여기 [송금] 버튼 누르세요", targetText: "송금"))
        #expect(IrreversibleActions.isIrreversible(nextAction: "이체하기를 누르세요", targetText: "이체하기"))
        #expect(IrreversibleActions.isIrreversible(nextAction: "결제하시면 됩니다", targetText: "결제"))
    }

    @Test("한국어 메시지/삭제 keyword")
    func koreanMessageDelete() {
        #expect(IrreversibleActions.isIrreversible(nextAction: "보내기 버튼", targetText: "보내기"))
        #expect(IrreversibleActions.isIrreversible(nextAction: "삭제하세요", targetText: "삭제"))
        #expect(IrreversibleActions.isIrreversible(nextAction: "탈퇴 진행", targetText: "탈퇴"))
    }

    @Test("영어 keyword — send/delete/transfer")
    func englishKeywords() {
        #expect(IrreversibleActions.isIrreversible(nextAction: "Click Send", targetText: "Send"))
        #expect(IrreversibleActions.isIrreversible(nextAction: "Press Delete", targetText: "Delete"))
        #expect(IrreversibleActions.isIrreversible(nextAction: "Confirm purchase", targetText: "Purchase"))
    }

    @Test("안전 동작 — false positive 없어야")
    func safeActions() {
        #expect(!IrreversibleActions.isIrreversible(nextAction: "여기 Slack 아이콘 누르세요", targetText: "Slack"))
        #expect(!IrreversibleActions.isIrreversible(nextAction: "환경설정 열기", targetText: "환경설정"))
        #expect(!IrreversibleActions.isIrreversible(nextAction: "검색창에 입력", targetText: "검색"))
    }

    @Test("case-insensitive — Send / SEND / send 모두 detect")
    func caseInsensitive() {
        #expect(IrreversibleActions.isIrreversible(nextAction: "SEND IT", targetText: "SEND"))
        #expect(IrreversibleActions.isIrreversible(nextAction: "send message", targetText: "send"))
    }
}

@Suite("Phase 7.0 — AnalysisResult default 호환성")
struct AnalysisResultPhase70Tests {

    @Test("v0.1 LLM 응답 (Phase 7.0 필드 없음) — default 값 박힘")
    func v01CompatibleDecode() throws {
        let json = """
        {
          "screen_state": "Chrome 열린 상태",
          "next_action": "여기 [Slack] 아이콘 누르세요",
          "target_text": "Slack",
          "reasoning": "Slack 앱 열기 의도"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(AnalysisResult.self, from: json)
        #expect(result.targetText == "Slack")
        // Phase 7.0 default 값 확인 — v0.1 응답에 없어도 안 깨짐
        #expect(result.taskComplete == false)
        #expect(result.requiresConfirmation == false)
        #expect(result.stepActionSummary == nil)
    }

    @Test("Phase 7.0 LLM 응답 — task_complete / requires_confirmation / step_action_summary 박힘")
    func phase70FullDecode() throws {
        let json = """
        {
          "screen_state": "Slack 메시지창",
          "next_action": "여기 [전송] 버튼 누르세요",
          "target_text": "전송",
          "reasoning": "메시지 전송",
          "task_complete": false,
          "requires_confirmation": true,
          "step_action_summary": "메시지 입력 완료, 전송 대기 중"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(AnalysisResult.self, from: json)
        #expect(result.requiresConfirmation == true)
        #expect(result.stepActionSummary == "메시지 입력 완료, 전송 대기 중")
        #expect(result.taskComplete == false)
    }

    @Test("encode round-trip — Phase 7.0 필드 보존")
    func roundTrip() throws {
        let original = AnalysisResult(
            screenState: "test",
            nextAction: "click",
            targetText: "Send",
            reasoning: "send msg",
            taskComplete: true,
            requiresConfirmation: true,
            stepActionSummary: "summary"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: data)
        #expect(decoded.taskComplete == true)
        #expect(decoded.requiresConfirmation == true)
        #expect(decoded.stepActionSummary == "summary")
    }
}

@Suite("Phase 7.0 — AnalyzeCoordinator SessionState scaffold")
struct AnalyzeCoordinatorSessionStateTests {

    @Test("초기 state — idle")
    func initialStateIsIdle() async {
        let coordinator = AnalyzeCoordinator(
            capture: Phase70Stub.Capture(),
            dispatcher: Phase70Stub.Dispatcher(),
            ocr: Phase70Stub.OCR(),
            ax: Phase70Stub.AX()
        )
        let state = await coordinator.snapshotState()
        #expect(state == .idle)
    }

    @Test("cancelSession — state .cancelled")
    func cancelClearsState() async {
        let coordinator = AnalyzeCoordinator(
            capture: Phase70Stub.Capture(),
            dispatcher: Phase70Stub.Dispatcher(),
            ocr: Phase70Stub.OCR(),
            ax: Phase70Stub.AX()
        )
        await coordinator.cancelSession(reason: .userEsc)
        let state = await coordinator.snapshotState()
        #expect(state == .cancelled(reason: .userEsc))
    }

    @Test("CancelReason — 4 종 Equatable")
    func cancelReasonCases() {
        #expect(AnalyzeCoordinator.CancelReason.userEsc == .userEsc)
        #expect(AnalyzeCoordinator.CancelReason.idleTimeout != .userEsc)
        #expect(AnalyzeCoordinator.CancelReason.error != .appQuit)
    }
}

/// Phase 7.0 scaffold tests용 minimal stubs. continueSession()는 Phase 7.1에서 진짜 wire.
private enum Phase70Stub {
    struct Capture: ScreenCaptureService {
        func captureCursorScreen() async throws -> (Data, DisplayGeometry) {
            throw ScreenCapture.CaptureError.noScreen
        }
    }
    struct Dispatcher: LLMDispatcher {
        func analyze(imageData: Data, imageSize: CGSize, instruction: String) async throws -> AnalysisResult {
            throw DispatcherError.invalidResponse("stub")
        }
    }
    struct OCR: OCRService {
        func recognize(pngData: Data, sentSize: CGSize) async throws -> [OCRBox] { [] }
    }
    struct AX: AXService {
        func queryAllElements() async throws -> [AXElement] { [] }
    }
}

@Suite("Phase 7.0 — StepSummary Codable")
struct StepSummaryTests {

    @Test("round-trip")
    func roundTrip() throws {
        let original = StepSummary(stepNumber: 2, actionTaken: "Slack 친구 [홍길동] 선택함")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StepSummary.self, from: data)
        #expect(decoded == original)
    }
}

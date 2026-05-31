//
//  AnalyzeCoordinator.swift
//  ScreenBridge — Phase 4.2
//
//  capture + dispatcher 흐름. 중복 trigger reject (actor isolation).
//
//  Phase 4.2는 단일 `.done`/`.failed` 반환. Phase 5.x에서 stage stream 가능.
//

import CoreGraphics
import Foundation

actor AnalyzeCoordinator {
    private let capture: ScreenCaptureService
    private let dispatcher: LLMDispatcher
    private let ocr: OCRService
    private let ax: AXService
    private var isRunning: Bool = false

    // Phase 7.0: SessionState scaffold. Transition은 7.1에서 wire (AppDelegate hotkey 분기).
    // 지금은 *snapshot 가능*만 — 외부 코드가 state 읽을 수 있으나 자동 transition X.
    enum SessionState: Sendable, Equatable {
        case idle
        case analyzing(stepIndex: Int)
        case waitingForUserClick(stepIndex: Int, deadlineAt: Date)
        case completed
        case cancelled(reason: CancelReason)
    }
    enum CancelReason: Sendable, Equatable {
        case userEsc, idleTimeout, error, appQuit
    }

    private var sessionState: SessionState = .idle
    private(set) var sessionID: String?
    private(set) var history: [StepSummary] = []

    init(
        capture: ScreenCaptureService = LiveScreenCapture(),
        dispatcher: LLMDispatcher,
        ocr: OCRService = VisionOCRService(),
        ax: AXService = LiveAXService()
    ) {
        self.capture = capture
        self.dispatcher = dispatcher
        self.ocr = ocr
        self.ax = ax
    }

    /// 외부 코드 (AppDelegate)가 state 읽을 때. await 강제 — race 차단 (synthesis risk #2).
    func snapshotState() -> SessionState { sessionState }

    /// Phase 7.0 stub. 7.1에서 진짜 transition 박음. 지금은 run()에 delegate —
    /// AppDelegate가 부르더라도 v0.1 single-shot 동작 그대로.
    func continueSession(_ req: AnalyzeRequest) async -> AnalyzeStage {
        Log.dispatcher.info("[session] continueSession called — Phase 7.0 stub, delegating to run()")
        return await run(req)
    }

    /// Test/diagnostic 용. Phase 7.1에서 실제 cancel 흐름 wire (esc / menu-bar item).
    func cancelSession(reason: CancelReason) {
        sessionState = .cancelled(reason: reason)
        sessionID = nil
        history.removeAll()
        Log.dispatcher.info("[session] cancel — reason=\(String(describing: reason), privacy: .public)")
    }

    /// Analyze 1회 실행. 진행 중이면 즉시 `.failed(.invalidResponse)` 반환.
    func run(_ req: AnalyzeRequest) async -> AnalyzeStage {
        if isRunning {
            Log.dispatcher.notice("[analyze] reject — 이미 진행 중")
            return .failed(.invalidResponse("이미 분석 중"))
        }
        isRunning = true
        defer { isRunning = false }

        Log.dispatcher.info(
            "[analyze] begin — instruction \(req.instruction.count, privacy: .public) chars"
        )
        let started = Date()

        // 1. capture
        let imageData: Data
        let geometry: DisplayGeometry
        do {
            (imageData, geometry) = try await capture.captureCursorScreen()
        } catch let err as ScreenCapture.CaptureError {
            Log.dispatcher.error("[analyze] capture failed: \(String(describing: err), privacy: .public)")
            switch err {
            case .permissionDenied:
                return .failed(.invalidResponse("permission_denied"))
            case .noScreen, .displayNotFound:
                return .failed(.invalidResponse("display_unavailable"))
            case .encodeFailed:
                return .failed(.invalidResponse("encode_failed"))
            }
        } catch {
            Log.dispatcher.error("[analyze] capture error: \(error.localizedDescription, privacy: .public)")
            return .failed(.invalidResponse(error.localizedDescription))
        }

        let captureElapsed = Date().timeIntervalSince(started)
        Log.dispatcher.info(
            "[analyze] captured \(imageData.count, privacy: .public) bytes in \(String(format: "%.1f", captureElapsed), privacy: .public)s"
        )

        // 2. dispatcher + OCR + AX 3개 병렬 (Phase 6.2 — AX matcher 추가).
        async let dispatcherFuture: AnalysisResult = dispatcher.analyze(
            imageData: imageData,
            imageSize: geometry.sentSize,
            instruction: req.instruction
        )
        async let ocrFuture: [OCRBox] = ocr.recognize(
            pngData: imageData,
            sentSize: geometry.sentSize
        )
        async let axFuture: [AXElement] = ax.queryAllElements()

        let result: AnalysisResult
        do {
            result = try await dispatcherFuture
        } catch let err as DispatcherError {
            Log.dispatcher.error("[analyze] dispatcher failed: \(String(describing: err), privacy: .public)")
            return .failed(err)
        } catch {
            Log.dispatcher.error("[analyze] dispatcher error: \(error.localizedDescription, privacy: .public)")
            return .failed(.invalidResponse(error.localizedDescription))
        }

        // OCR 실패는 fatal X — AX 또는 LLM coords fallback.
        let ocrBoxes: [OCRBox]
        do {
            ocrBoxes = try await ocrFuture
        } catch {
            Log.dispatcher.error("[analyze] OCR failed (not fatal): \(error.localizedDescription, privacy: .public)")
            ocrBoxes = []
        }

        // AX 실패도 fatal X — 권한 거부 또는 일부 앱 (Electron 등) tree 비어있음.
        let axElements: [AXElement]
        do {
            axElements = try await axFuture
        } catch {
            Log.dispatcher.notice("[analyze] AX failed (not fatal): \(error.localizedDescription, privacy: .public)")
            axElements = []
        }

        // 3. target_text 매칭 — OCR + AX 합집합 candidate (Phase 6.2).
        // OCRBox → MatchCandidate (sent→logical pt 변환)
        let ocrCandidates: [MatchCandidate] = ocrBoxes.compactMap { box in
            let boxInt = [
                Int(box.rectInSentImage.origin.x.rounded()),
                Int(box.rectInSentImage.origin.y.rounded()),
                Int(box.rectInSentImage.width.rounded()),
                Int(box.rectInSentImage.height.rounded()),
            ]
            guard let logical = geometry.logicalRectFromSentBox(boxInt) else { return nil }
            return MatchCandidate(
                text: box.text,
                rectInLogicalPt: logical,
                confidence: box.confidence,
                source: .ocr
            )
        }
        // AXElement → MatchCandidate (이미 logical pt, confidence 1.0)
        let axCandidates: [MatchCandidate] = axElements.map { el in
            MatchCandidate(
                text: el.text,
                rectInLogicalPt: el.rectInLogicalPt,
                confidence: 1.0,
                source: .ax(role: el.role)
            )
        }
        let allCandidates = ocrCandidates + axCandidates

        // Spatial fusion: LLM coords → logical pt hint.
        let llmHintLogical: CGRect? = result.coordinates.flatMap { coords in
            guard coords.count == 4 else { return nil }
            return geometry.logicalRectFromSentBox(coords)
        }
        // Preferred role: LLM이 명시한 target_role 우선, 없으면 instruction keyword 추론.
        // LLM target_role이 더 정확 (instruction 분석 + 화면 context 둘 다 봄).
        let preferredRole: String?
        if let llmRole = result.targetRole, !llmRole.isEmpty {
            preferredRole = llmRole
            Log.dispatcher.info("[match] preferred role from LLM: \(llmRole, privacy: .public)")
        } else if let inferred = ElementMatcher.inferPreferredRole(from: req.instruction) {
            preferredRole = inferred
            Log.dispatcher.info("[match] preferred role from instruction keyword: \(inferred, privacy: .public)")
        } else {
            preferredRole = nil
        }
        // Multi-target: top 2 distinct candidates. 사용자가 1번/2번 시각 선택 (user-in-the-loop).
        let matches = ElementMatcher.matchTop(
            targetText: result.targetText,
            candidates: allCandidates,
            llmHintRect: llmHintLogical,
            preferredRole: preferredRole,
            maxResults: 2
        )

        let totalElapsed = Date().timeIntervalSince(started)
        let matchTag = matches.isEmpty ? "LLM-fallback" : matches[0].sourceTag
        Log.dispatcher.info(
            "[analyze] complete \(String(format: "%.1f", totalElapsed), privacy: .public)s — target_text=\"\(result.targetText, privacy: .public)\" \(matchTag, privacy: .public) matches=\(matches.count, privacy: .public) (ocr=\(ocrBoxes.count, privacy: .public) ax=\(axElements.count, privacy: .public))"
        )
        return .done(result: result, geometry: geometry, matches: matches)
    }
}

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
        let matched = ElementMatcher.match(
            targetText: result.targetText,
            candidates: allCandidates,
            llmHintRect: llmHintLogical
        )

        let totalElapsed = Date().timeIntervalSince(started)
        let matchTag = matched?.sourceTag ?? "LLM-fallback"
        Log.dispatcher.info(
            "[analyze] complete \(String(format: "%.1f", totalElapsed), privacy: .public)s — target_text=\"\(result.targetText, privacy: .public)\" \(matchTag, privacy: .public) (ocr=\(ocrBoxes.count, privacy: .public) ax=\(axElements.count, privacy: .public))"
        )
        return .done(result: result, geometry: geometry, matched: matched)
    }
}

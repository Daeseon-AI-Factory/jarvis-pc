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
    private var isRunning: Bool = false

    init(
        capture: ScreenCaptureService = LiveScreenCapture(),
        dispatcher: LLMDispatcher,
        ocr: OCRService = VisionOCRService()
    ) {
        self.capture = capture
        self.dispatcher = dispatcher
        self.ocr = ocr
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

        // 2. dispatcher + OCR 병렬 — 둘 다 captured imageData에 의존, 서로 독립.
        async let dispatcherFuture: AnalysisResult = dispatcher.analyze(
            imageData: imageData,
            imageSize: geometry.sentSize,
            instruction: req.instruction
        )
        async let ocrFuture: [OCRBox] = ocr.recognize(
            pngData: imageData,
            sentSize: geometry.sentSize
        )

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

        // OCR 실패는 fatal X — LLM coordinates fallback 가능 (v0.1 dogfooding 자료).
        let ocrBoxes: [OCRBox]
        do {
            ocrBoxes = try await ocrFuture
        } catch {
            Log.dispatcher.error("[analyze] OCR failed (not fatal): \(error.localizedDescription, privacy: .public)")
            ocrBoxes = []
        }

        // 3. target_text 매칭 — deterministic 좌표 (99% 핵심).
        // Spatial fusion (Phase 6.1 wrong-box 차단): LLM이 coordinates 줬으면 그 영역 근처
        // OCR 박스만 candidate. 화면 여러 영역에 같은 텍스트 있을 때 사용자 intent 영역 고름.
        let llmHintRect: CGRect? = result.coordinates.flatMap { coords in
            guard coords.count == 4 else { return nil }
            return CGRect(x: coords[0], y: coords[1], width: coords[2], height: coords[3])
        }
        let matched = ElementMatcher.match(
            targetText: result.targetText,
            candidates: ocrBoxes,
            geometry: geometry,
            llmHintRect: llmHintRect
        )

        let totalElapsed = Date().timeIntervalSince(started)
        let matchTag = matched != nil ? "OCR-matched" : "LLM-fallback"
        Log.dispatcher.info(
            "[analyze] complete \(String(format: "%.1f", totalElapsed), privacy: .public)s — target_text=\"\(result.targetText, privacy: .public)\" \(matchTag, privacy: .public)"
        )
        return .done(result: result, geometry: geometry, matchedRect: matched)
    }
}

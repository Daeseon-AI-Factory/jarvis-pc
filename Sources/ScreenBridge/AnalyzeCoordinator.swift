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
    private var isRunning: Bool = false

    init(capture: ScreenCaptureService = LiveScreenCapture(), dispatcher: LLMDispatcher) {
        self.capture = capture
        self.dispatcher = dispatcher
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

        // 2. dispatcher (8-15s 예상)
        do {
            let result = try await dispatcher.analyze(
                imageData: imageData,
                imageSize: geometry.sentSize,
                instruction: req.instruction
            )
            let totalElapsed = Date().timeIntervalSince(started)
            Log.dispatcher.info(
                "[analyze] complete \(String(format: "%.1f", totalElapsed), privacy: .public)s — target_text=\"\(result.targetText, privacy: .public)\""
            )
            return .done(result: result, geometry: geometry)
        } catch let err as DispatcherError {
            Log.dispatcher.error("[analyze] dispatcher failed: \(String(describing: err), privacy: .public)")
            return .failed(err)
        } catch {
            Log.dispatcher.error("[analyze] dispatcher error: \(error.localizedDescription, privacy: .public)")
            return .failed(.invalidResponse(error.localizedDescription))
        }
    }
}

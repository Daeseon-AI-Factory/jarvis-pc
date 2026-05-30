//
//  ScreenCaptureService.swift
//  ScreenBridge — Phase 4.2
//
//  Capture protocol — AnalyzeCoordinator unit test에 mock 주입 가능.
//

import CoreGraphics
import Foundation

protocol ScreenCaptureService: Sendable {
    func captureCursorScreen() async throws -> (Data, DisplayGeometry)
}

/// Production 구현 — ScreenCapture enum static func로 forward.
struct LiveScreenCapture: ScreenCaptureService {
    func captureCursorScreen() async throws -> (Data, DisplayGeometry) {
        try await ScreenCapture.captureCursorScreen()
    }
}

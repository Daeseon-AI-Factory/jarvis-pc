//
//  Permissions.swift
//  ScreenBridge — Phase 3.1
//
//  Screen Recording + Accessibility 권한 trigger 및 status query.
//  Sweep advice: AppDelegate startup에서 Screen Recording 권한 0.5단계 빨리 trigger
//  (Phase 3 capture 작성 도중 silent fail 회피).
//

import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {

    // MARK: - Screen Recording (ScreenCaptureKit 위해 필수)

    static func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 권한 없으면 macOS 다이얼로그 trigger. 사용자 응답은 비동기 (즉시 false 반환 후
    /// 다음 launch에 true 가능). 거부 후 다시 호출해도 다이얼로그 *재출현 X* — Settings 안내.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Accessibility (AXUIElement, Phase 6.2 OCR fallback 위해 향후)

    static func hasAccessibility() -> Bool {
        // `kAXTrustedCheckOptionPrompt`는 Swift 6 strict concurrency가 extern var로 잡아 거부 —
        // string literal 사용 (Apple 표준 "AXTrustedCheckOptionPrompt").
        let opts: CFDictionary = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let opts: CFDictionary = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

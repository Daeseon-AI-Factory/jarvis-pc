//
//  TriggerContext.swift
//  ScreenBridge — Phase 3.1
//
//  ⌥Space hotkey 시점의 cursor + screen + displayID snapshot. Analyze 시점엔 cursor가
//  TriggerPanel monitor로 옮겨갈 수 있어 *hotkey 시점*만 신뢰 (Tauri Layer 10 회피).
//

import AppKit
import CoreGraphics

struct TriggerContext: Sendable {
    let cursor: NSPoint        // 전역 좌표 (NSEvent.mouseLocation, bottom-left origin)
    let screen: ScreenSnapshot
    let timestamp: Date

    struct ScreenSnapshot: Sendable {
        let frame: NSRect              // logical points, bottom-left origin
        let backingScaleFactor: CGFloat
        let displayID: CGDirectDisplayID  // SCDisplay ↔ NSScreen 매칭용
    }
}

/// 마지막 hotkey 시점 context. `HotKeyManager.onTrigger` 콜백 즉시 `capture()` 호출.
@MainActor
enum LastTriggerContext {
    private(set) static var current: TriggerContext?

    static func capture() {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else {
            current = nil
            Log.app.error("[trigger] no NSScreen available")
            return
        }

        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()

        current = TriggerContext(
            cursor: cursor,
            screen: TriggerContext.ScreenSnapshot(
                frame: screen.frame,
                backingScaleFactor: screen.backingScaleFactor,
                displayID: displayID
            ),
            timestamp: Date()
        )

        Log.app.info(
            "[trigger] cursor=(\(Int(cursor.x), privacy: .public),\(Int(cursor.y), privacy: .public)) screen=\(Int(screen.frame.width), privacy: .public)x\(Int(screen.frame.height), privacy: .public)@\(String(format: "%.1f", screen.backingScaleFactor), privacy: .public)x display=\(displayID, privacy: .public)"
        )
    }
}

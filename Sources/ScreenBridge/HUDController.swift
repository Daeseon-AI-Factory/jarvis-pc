//
//  HUDController.swift
//  ScreenBridge — Phase 5.0
//
//  HUD overlay window lifecycle. present(annotation, on screen) / dismiss().
//  Phase 5.0: hardcode 빨간 박스 1개 (화면 중앙). Phase 5.x: AnalysisResult 좌표.
//
//  좌표 패턴:
//  - HUDOverlayWindow.setFrame(screen.frame) — screen.frame은 global AppKit, raw setFrame OK.
//  - annotation.rect는 SwiftUI View 내부의 screen-local top-left. View frame이 screen 전체라
//    그대로 좌표 사용.
//  - ⚠️ Phase 5.x/6.x에서 LLM sent px 좌표 → `DisplayGeometry.logicalRectFromSentBox` → annotation.rect.
//    raw `setFrame(localRect)` 절대 금지 (verify fix lesson, Tauri Layer 9).
//

import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private var window: HUDOverlayWindow?
    private(set) var isShowing: Bool = false

    func present(annotation: HUDAnnotation, on screen: NSScreen) {
        if window == nil {
            window = HUDOverlayWindow()
        }
        guard let win = window else { return }

        win.orderOut(nil)
        // screen.frame은 global AppKit (외부 monitor x=1440 등) — raw setFrame 안전.
        win.setFrame(screen.frame, display: false)
        win.contentView = NSHostingView(rootView: HUDOverlayView(annotation: annotation))
        win.orderFrontRegardless()   // ⚠️ makeKeyAndOrderFront 절대 금지 — focus 안 뺏음.

        isShowing = true
        Log.app.info(
            "[hud] present on screen=\(Int(screen.frame.width), privacy: .public)x\(Int(screen.frame.height), privacy: .public)@(\(Int(screen.frame.origin.x), privacy: .public),\(Int(screen.frame.origin.y), privacy: .public)) — rect=(\(Int(annotation.rect.origin.x), privacy: .public),\(Int(annotation.rect.origin.y), privacy: .public),\(Int(annotation.rect.width), privacy: .public),\(Int(annotation.rect.height), privacy: .public))"
        )
    }

    func dismiss() {
        window?.orderOut(nil)
        window?.contentView = nil
        isShowing = false
        Log.app.info("[hud] dismiss")
    }

    /// Phase 5.0 hardcode placeholder — 사용자 Analyze 직후 *화면 중앙*에 빨간 박스 1개.
    /// dispatcher 무관 NSWindow 본질 5개 (Layer 1/4/7/8/9) 검증 = 안경 메타포 *첫 시각화*.
    func presentPlaceholderCenter(on screen: NSScreen) {
        let boxW: CGFloat = 300
        let boxH: CGFloat = 50
        let local = CGRect(
            x: (screen.frame.width - boxW) / 2,
            y: (screen.frame.height - boxH) / 2,
            width: boxW,
            height: boxH
        )
        present(annotation: HUDAnnotation(rect: local), on: screen)
    }
}

//
//  HUDController.swift
//  ScreenBridge — Phase 4.2 (rewrite from 5.0)
//
//  HUD overlay lifecycle. present(content, on screen) 단일 method + 3 helpers.
//  Phase 5.0의 presentPlaceholderCenter 유지 (호환).
//

import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private var window: HUDOverlayWindow?
    private(set) var isShowing: Bool = false

    /// 단일 entry — `HUDContent` (loading / annotated / error).
    /// `screen.frame`은 global AppKit이라 raw `setFrame` 안전 (verify fix lesson 적용 범위 밖).
    func present(content: HUDContent, on screen: NSScreen) {
        if window == nil {
            window = HUDOverlayWindow()
        }
        guard let win = window else { return }

        win.orderOut(nil)
        win.setFrame(screen.frame, display: false)
        win.contentView = NSHostingView(rootView: HUDOverlayView(content: content))
        win.orderFrontRegardless()   // makeKeyAndOrderFront 절대 금지

        isShowing = true
        currentContent = content
        Log.app.info(
            "[hud] present content type=\(self.contentKind(content), privacy: .public) on screen \(Int(screen.frame.width), privacy: .public)x\(Int(screen.frame.height), privacy: .public)@(\(Int(screen.frame.origin.x), privacy: .public),\(Int(screen.frame.origin.y), privacy: .public))"
        )
    }

    func dismiss() {
        window?.orderOut(nil)
        window?.contentView = nil
        isShowing = false
        currentContent = nil
        Log.app.info("[hud] dismiss")
    }

    func presentLoading(message: String, on screen: NSScreen) {
        present(content: .loading(message: message), on: screen)
    }

    func presentAnnotation(_ annotation: HUDAnnotation, on screen: NSScreen) {
        present(content: .annotated(annotation), on: screen)
    }

    func presentError(message: String, on screen: NSScreen) {
        present(content: .error(message: message), on: screen)
    }

    /// Phase 7.3: 완료 pill (초록 ✓). 2.5s 후 자동 dismiss.
    func presentCompletion(message: String, on screen: NSScreen, autoDismissAfter seconds: TimeInterval = 2.5) {
        present(content: .completion(message: message), on: screen)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            // 그 사이 새 content 떠있으면 dismiss 안 함 (race 차단).
            guard case .completion = self?.currentContent else { return }
            self?.dismiss()
        }
    }

    /// 현재 보이는 content (race 차단용 — auto-dismiss가 새 task 박은 거 지울까봐).
    private var currentContent: HUDContent?

    /// Phase 5.0 호환 — 화면 중앙 빨간 박스 hardcode.
    func presentPlaceholderCenter(on screen: NSScreen) {
        let boxW: CGFloat = 300
        let boxH: CGFloat = 50
        let local = CGRect(
            x: (screen.frame.width - boxW) / 2,
            y: (screen.frame.height - boxH) / 2,
            width: boxW,
            height: boxH
        )
        presentAnnotation(HUDAnnotation(rect: local), on: screen)
    }

    private func contentKind(_ content: HUDContent) -> String {
        switch content {
        case .loading: return "loading"
        case .annotated: return "annotated"
        case .error: return "error"
        case .completion: return "completion"
        }
    }
}

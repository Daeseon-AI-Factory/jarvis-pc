//
//  SessionInspectorPanel.swift
//  ScreenBridge — v0.3 Session Inspector NSPanel wrapper
//
//  HUDOverlayWindow와 다름:
//  - Floating utility panel (사용자가 *클릭* 가능 — canBecomeKey=true)
//  - title bar 박힘 (close/move 가능)
//  - 단일 instance — 매번 만들지 X, toggle
//

import AppKit
import SwiftUI

@MainActor
final class SessionInspectorPanel {
    static let shared = SessionInspectorPanel()

    private var window: NSPanel?

    var isVisible: Bool { window?.isVisible ?? false }

    private init() {}

    func toggle(onCancel: @escaping () -> Void) {
        if let win = window, win.isVisible {
            win.orderOut(nil)
            return
        }
        present(onCancel: onCancel)
    }

    func present(onCancel: @escaping () -> Void) {
        if window == nil {
            window = makeWindow(onCancel: onCancel)
        }
        guard let win = window else { return }
        win.makeKeyAndOrderFront(nil)
        win.center()
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    private func makeWindow(onCancel: @escaping () -> Void) -> NSPanel {
        let view = SessionInspectorView(state: InspectorState.shared, onCancel: onCancel)
        let hosting = NSHostingController(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Session Inspector"
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.level = .floating
        panel.setFrameAutosaveName("ScreenBridge.SessionInspector")
        return panel
    }
}

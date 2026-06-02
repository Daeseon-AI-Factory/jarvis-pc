//
//  SettingsWindow.swift
//  ScreenBridge — v0.3 환경설정 NSWindow wrapper (단일 instance)
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    private init() {}

    func showOrFocus() {
        if window == nil {
            window = makeWindow()
        }
        guard let win = window else { return }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.center()
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        // styleMask는 *init 시점*에 박음 — 박은 후 갱신은 contentView invalidate.
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ScreenBridge 환경설정"
        win.setFrameAutosaveName("ScreenBridge.Settings")
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .moveToActiveSpace]

        // NSHostingView 박음 — NSHostingController + contentViewController 박은 거보다
        // *NSHostingView로 contentView 직접 박는 게* layout race 차단.
        let hosting = NSHostingView(rootView: SettingsView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        win.contentView = hosting
        if let contentView = win.contentView {
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: contentView.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }
        return win
    }
}

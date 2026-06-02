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
        let view = SettingsView()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "ScreenBridge 환경설정"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 520, height: 520))
        win.setFrameAutosaveName("ScreenBridge.Settings")
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .moveToActiveSpace]
        return win
    }
}

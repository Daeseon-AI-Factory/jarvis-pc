import AppKit
import OSLog

/// 앱 lifecycle 주도. menu-bar only (.accessory) + NSStatusItem + global hotkey +
/// trigger panel 소유.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotKey = HotKeyManager()
    private var triggerPanel: TriggerPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // dock 안 보임, menu bar only. SwiftPM엔 Info.plist LSUIElement를 못
        // 박으니 런타임에 설정 — 더 안정적이기도 하다.
        NSApp.setActivationPolicy(.accessory)

        setUpStatusItem()
        triggerPanel = TriggerPanel()

        hotKey.onTrigger = { [weak self] in
            // hotkey 시점에 cursor + screen + displayID 즉시 capture — Tauri Layer 10 회피.
            // analyze 시점엔 cursor가 panel monitor로 옮겨가 있음.
            LastTriggerContext.capture()
            self?.toggleTriggerPanel()
        }
        hotKey.register()

        // 권한 startup trigger (sweep advice: 0.5단계 빨리 — Phase 3.1 작성 도중 silent fail 회피).
        // Accessibility는 Phase 6.2 (AXUIElement) 시점에 별도 요청.
        Task { @MainActor in
            if !Permissions.hasScreenRecording() {
                Log.app.notice("Screen Recording 권한 없음 — 다이얼로그 trigger")
                Permissions.requestScreenRecording()
            } else {
                Log.app.info("Screen Recording 권한 OK")
            }
        }

        Log.app.info("launched — menu-bar accessory + ⌥Space hotkey ready")
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // SF Symbol — 안경 메타포. 없으면 텍스트 fallback.
            button.image = NSImage(
                systemSymbolName: "eyeglasses",
                accessibilityDescription: "ScreenBridge"
            )
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Trigger now (⌥Space)",
            action: #selector(triggerNow),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Open sessions folder",
            action: #selector(openSessions),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit ScreenBridge",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        // menu의 target은 각 item이 AppDelegate를 가리키도록.
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func toggleTriggerPanel() {
        guard let panel = triggerPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.showCentered()
        }
    }

    @objc private func triggerNow() {
        toggleTriggerPanel()
    }

    @objc private func openSessions() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("com.screenbridge.app/sessions", isDirectory: true)
        guard let dir = base else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

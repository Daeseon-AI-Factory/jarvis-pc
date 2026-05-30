import AppKit
import OSLog

/// 앱 lifecycle 주도. menu-bar only (.accessory) + NSStatusItem + global hotkey +
/// trigger panel 소유.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotKey = HotKeyManager()
    private var triggerPanel: TriggerPanel?
    private let hud = HUDController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // dock 안 보임, menu bar only. SwiftPM엔 Info.plist LSUIElement를 못
        // 박으니 런타임에 설정 — 더 안정적이기도 하다.
        NSApp.setActivationPolicy(.accessory)

        setUpStatusItem()
        triggerPanel = TriggerPanel(onAnalyze: { [weak self] instruction in
            self?.handleAnalyze(instruction: instruction)
        })

        hotKey.onTrigger = { [weak self] in
            // hotkey 시점에 cursor + screen + displayID 즉시 capture — Tauri Layer 10 회피.
            LastTriggerContext.capture()
            self?.handleHotkey()
        }
        hotKey.register()

        // 권한 startup trigger (sweep advice: 0.5단계 빨리 — Phase 3.1 작성 도중 silent fail 회피).
        // macOS TCC는 'Don't Allow' 누르면 다이얼로그 *영구히 재출현 X* → 거부 시 Settings 안내.
        // verify workflow HIGH finding.
        Task { @MainActor in
            if Permissions.hasScreenRecording() {
                Log.app.info("Screen Recording 권한 OK")
                return
            }
            Log.app.notice("Screen Recording 권한 없음 — 다이얼로그 trigger")
            Permissions.requestScreenRecording()
            // 다이얼로그가 비동기라 hasScreenRecording은 잠시 후 다시 확인 필요.
            // 1초 후 재확인 + 여전히 없으면 Settings 안내.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if !Permissions.hasScreenRecording() {
                    Log.app.error("Screen Recording 권한 거부 — Settings > Privacy & Security > Screen Recording에서 ScreenBridge 토글 후 재시작 필요")
                    Permissions.openScreenRecordingSettings()
                }
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

    /// ⌥+Space 흐름: HUD 떠있으면 dismiss, 아니면 panel toggle.
    /// (Phase 5.0 — Analyze 누르면 HUD 뜨고 panel close → 다시 ⌥+Space로 HUD 닫음)
    private func handleHotkey() {
        if hud.isShowing {
            hud.dismiss()
            return
        }
        toggleTriggerPanel()
    }

    /// Analyze 콜백 — Phase 5.0은 *hardcode 빨간 박스 1개* 화면 중앙에.
    /// Phase 4.2에서 capture + dispatcher + DisplayGeometry로 진짜 분석 연결.
    private func handleAnalyze(instruction: String) {
        Log.panel.info("analyze submit (Phase 5.0 placeholder): \(instruction.count, privacy: .public) chars — HUD hardcode center")
        guard let screen = cursorScreen() else {
            Log.app.error("[analyze] no NSScreen for HUD — fallback to first")
            return
        }
        hud.presentPlaceholderCenter(on: screen)
    }

    /// LastTriggerContext의 displayID 우선, 없으면 cursor 위치, 최후 screens.first.
    /// ⚠️ NSScreen.main 절대 금지 (Tauri Layer 9).
    private func cursorScreen() -> NSScreen? {
        if let ctx = LastTriggerContext.current {
            if let s = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == ctx.screen.displayID
            }) {
                return s
            }
        }
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) }
            ?? NSScreen.screens.first
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

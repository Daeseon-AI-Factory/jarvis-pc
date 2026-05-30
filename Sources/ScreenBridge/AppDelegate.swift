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

    /// GEMINI_API_KEY 있으면 dispatcher 생성. 없으면 handleAnalyze에서 HUD 에러.
    private let dispatcher: GeminiDispatcher? = GeminiDispatcher.fromEnvironment()
    private lazy var coordinator: AnalyzeCoordinator? = {
        guard let dispatcher else {
            Log.dispatcher.error("GEMINI_API_KEY 없음 — AnalyzeCoordinator 생성 실패. .env 또는 process env 확인.")
            return nil
        }
        Log.dispatcher.info("AnalyzeCoordinator ready — Gemini dispatcher loaded")
        return AnalyzeCoordinator(dispatcher: dispatcher)
    }()

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

        // Gemini TLS/DNS pre-warm — 첫 analyze 호출 ~1-2s 단축.
        if let dispatcher {
            Task.detached {
                await dispatcher.prewarm()
            }
        }

        // 권한 startup trigger — Screen Recording + Accessibility (Phase 6.2 AX matcher용).
        Task { @MainActor in
            if Permissions.hasScreenRecording() {
                Log.app.info("Screen Recording 권한 OK")
            } else {
                Log.app.notice("Screen Recording 권한 없음 — 다이얼로그 trigger")
                Permissions.requestScreenRecording()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if !Permissions.hasScreenRecording() {
                        Log.app.error("Screen Recording 권한 거부 — Settings > Privacy > Screen Recording 토글 후 재시작 필요")
                        Permissions.openScreenRecordingSettings()
                    }
                }
            }

            // Accessibility 권한 — Phase 6.2 AX matcher 핵심. 거부해도 OCR matcher만으로 동작 (graceful).
            if Permissions.hasAccessibility() {
                Log.app.info("Accessibility 권한 OK — AX matcher 활성 (Dock 아이콘 deterministic)")
            } else {
                Log.app.notice("Accessibility 권한 없음 — 다이얼로그 trigger (AX matcher 비활성, OCR만으로 동작)")
                Permissions.requestAccessibility()
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

    /// Analyze 콜백 — Phase 4.2: 진짜 capture + dispatcher + HUD.
    /// 1. loading HUD 즉시
    /// 2. AnalyzeCoordinator.run async (capture + Gemini 8-15s)
    /// 3. .done: coordinates → DisplayGeometry → 빨간 박스 / .failed: 한국어 에러 pill
    /// 4. ⌥+Space로 dismiss
    private func handleAnalyze(instruction: String) {
        Log.panel.info("analyze submit: \(instruction.count, privacy: .public) chars")
        guard let screen = cursorScreen() else {
            Log.app.error("[analyze] no NSScreen for HUD")
            return
        }

        // dispatcher 없으면 에러 즉시
        guard let coordinator else {
            hud.presentError(
                message: "AI 키가 없어요.\n.env 파일에 GEMINI_API_KEY를 추가해주세요.",
                on: screen
            )
            return
        }

        // 1. loading HUD — 친화 메시지 + 예상 시간 (사용자 burden 작게).
        hud.presentLoading(message: "AI에 물어보는 중... (3~5초)", on: screen)
        let req = AnalyzeRequest(instruction: instruction, triggeredAt: Date())

        Task { @MainActor in
            let stage = await coordinator.run(req)
            switch stage {
            case .done(let result, let geometry, let matches):
                // 1. OCR/AX matched (deterministic) — bubble + alternatives (multi-target overlay)
                if let primary = matches.first {
                    // Alternative — matches[1..] (있으면)
                    let alts: [HUDAnnotation.Alternative] = matches.dropFirst().enumerated().map { idx, m in
                        HUDAnnotation.Alternative(rect: m.rect, sourceTag: m.sourceTag, number: idx + 2)
                    }
                    Log.app.info("[analyze] HUD annotated (\(primary.sourceTag, privacy: .public)) — target_text=\"\(result.targetText, privacy: .public)\" alts=\(alts.count, privacy: .public)")
                    self.hud.presentAnnotation(
                        HUDAnnotation(
                            rect: primary.rect,
                            nextAction: result.nextAction,
                            sourceTag: primary.sourceTag,
                            alternatives: alts
                        ),
                        on: screen
                    )
                    return
                }
                // 2. fallback — LLM 추정 coordinates (있으면)
                if let coords = result.coordinates,
                   let local = geometry.logicalRectFromSentBox(coords) {
                    Log.app.info("[analyze] HUD annotated (LLM-fallback) — target_text=\"\(result.targetText, privacy: .public)\"")
                    self.hud.presentAnnotation(
                        HUDAnnotation(
                            rect: local,
                            nextAction: result.nextAction,
                            sourceTag: "LLM"
                        ),
                        on: screen
                    )
                    return
                }
                // 3. 둘 다 실패 — 한국어 친화 에러. 「」 corner quote (postposition 회피).
                Log.app.notice("[analyze] no match (OCR + LLM coords both nil) — target_text=\"\(result.targetText, privacy: .public)\"")
                let truncated = result.targetText.count > 30
                    ? String(result.targetText.prefix(30)) + "…"
                    : result.targetText
                self.hud.presentError(
                    message: "화면에서 「\(truncated)」을(를) 찾을 수 없었어요.\n다시 시도하거나 다른 화면에서 시도해주세요.",
                    on: screen
                )
            case .failed(let err):
                let msg = UserMessage.from(err)
                Log.app.error("[analyze] failed → \(msg, privacy: .public)")
                self.hud.presentError(message: msg, on: screen)
            case .capturing, .analyzing:
                break   // Phase 4.2 stream 모드 아님
            }
        }
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

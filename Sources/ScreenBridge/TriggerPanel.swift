import AppKit
import OSLog
import SwiftUI

/// Trigger Panel 윈도우. ⌥+Space로 토글. 일반 윈도우 (transparent X) — HUD
/// overlay는 Phase 5에서 별도 NSWindow. SwiftUI content를 NSHostingView로 담는다.
///
/// NSPanel (not NSWindow) 사용 이유: nonactivating + floating + 다른 앱 위에
/// 뜨면서 그 앱의 key focus를 덜 뺏는다. 단 textarea 입력 위해 becomesKey 허용.
@MainActor
final class TriggerPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.title = "ScreenBridge"
        self.titlebarAppearsTransparent = true
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false

        let root = TriggerPanelView(onCancel: { [weak self] in
            self?.orderOut(nil)
        })
        self.contentView = NSHostingView(rootView: root)
    }

    /// cursor 있는 화면 중앙에 띄운다 (multi-monitor — 사용자가 본 화면).
    func showCentered() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        if let screen {
            let f = screen.visibleFrame
            let size = self.frame.size
            let origin = NSPoint(
                x: f.midX - size.width / 2,
                y: f.midY - size.height / 2
            )
            self.setFrameOrigin(origin)
        }
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct TriggerPanelView: View {
    var onCancel: () -> Void
    @State private var instruction: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI가 뭐라 했나?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $instruction)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)  // ESC
                Button("Analyze") {
                    // Phase 4.2에서 AnalyzeCoordinator 호출 + 결과 HUD. 지금은 placeholder.
                    Log.panel.info("analyze submit (placeholder): \(instruction.count, privacy: .public) chars")
                }
                .keyboardShortcut(.defaultAction)  // ⌘Return
                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520, height: 280)
    }
}

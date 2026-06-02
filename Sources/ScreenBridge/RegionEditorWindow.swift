//
//  RegionEditorWindow.swift
//  ScreenBridge — v0.3 Layer 3 Region drag UI
//
//  사용자가 *민감 영역* 박는 UI:
//  - 전체 화면 cover 박힌 반투명 NSWindow + NSView
//  - 드래그로 박스 그림 → CGRect → PrivacySettings.addSensitiveRegion
//  - 기존 박힌 영역은 빨강 visible (사용자 click으로 remove)
//  - ESC 또는 Done 버튼으로 종료
//
//  multi-monitor: 현재 *cursor 있는 display*만 박음 (사용자가 *해당 화면*에서 박은 거).
//

import AppKit

@MainActor
final class RegionEditorWindow: NSObject {
    static let shared = RegionEditorWindow()

    private var window: RegionEditorPanel?
    private var view: RegionEditorView?

    private override init() { super.init() }

    func present() {
        if window == nil {
            makeWindow()
        }
        guard let win = window else { return }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        view?.refresh()
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    private func makeWindow() {
        // cursor 있는 display 박음
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let win = RegionEditorPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.acceptsMouseMovedEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()

        let editorView = RegionEditorView(
            displayID: displayID,
            screenFrame: screen.frame,
            onDone: { [weak self] in
                self?.dismiss()
            }
        )
        win.contentView = editorView
        self.window = win
        self.view = editorView
    }
}

/// canBecomeKey for key event (ESC).
final class RegionEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 드래그 박스 + 박힌 영역 표시 + key handler.
final class RegionEditorView: NSView {
    let displayID: UInt32
    let screenFrame: NSRect
    var onDone: () -> Void

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?

    init(displayID: UInt32, screenFrame: NSRect, onDone: @escaping () -> Void) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.onDone = onDone
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() { needsDisplay = true }

    // MARK: - Mouse handlers

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
        guard let start = dragStart, let end = dragCurrent else { return }
        let rectLocal = rect(from: start, to: end)
        guard rectLocal.width > 10 && rectLocal.height > 10 else { return }

        // local view pt → screen-global pt (screenFrame.origin offset)
        let globalRect = NSRect(
            x: rectLocal.origin.x + screenFrame.origin.x,
            y: rectLocal.origin.y + screenFrame.origin.y,
            width: rectLocal.width,
            height: rectLocal.height
        )

        // PrivacySettings에 박음 (MainActor).
        Task { @MainActor in
            PrivacySettings.shared.addSensitiveRegion(globalRect, displayID: self.displayID)
            self.refresh()
        }
    }

    override func keyDown(with event: NSEvent) {
        // ESC = 27, Return = 36
        if event.keyCode == 53 || event.keyCode == 36 {
            onDone()
        } else if event.keyCode == 51 || event.keyCode == 117 {
            // Delete / forward delete — 마지막 영역 제거
            Task { @MainActor in
                var current = PrivacySettings.shared.sensitiveRegionsAll[self.displayID] ?? []
                _ = current.popLast()
                PrivacySettings.shared.sensitiveRegionsAll[self.displayID] = current
                self.refresh()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 반투명 검은 background
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
        ctx.fill(bounds)

        // 박힌 영역 (빨강 fill + label)
        let saved = PrivacySettings.shared.sensitiveRegionsForScreen(displayID: displayID)
        for (idx, region) in saved.enumerated() {
            let local = NSRect(
                x: region.origin.x - screenFrame.origin.x,
                y: region.origin.y - screenFrame.origin.y,
                width: region.width,
                height: region.height
            )
            ctx.setFillColor(CGColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 0.5))
            ctx.fill(local)
            ctx.setStrokeColor(CGColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1))
            ctx.setLineWidth(2)
            ctx.stroke(local)

            // label
            let label = "#\(idx + 1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let attrStr = NSAttributedString(string: label, attributes: attrs)
            attrStr.draw(at: NSPoint(x: local.minX + 6, y: local.maxY - 22))
        }

        // 진행 중 드래그 박스 (주황)
        if let start = dragStart, let current = dragCurrent {
            let r = rect(from: start, to: current)
            ctx.setFillColor(CGColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.35))
            ctx.fill(r)
            ctx.setStrokeColor(CGColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1))
            ctx.setLineWidth(2)
            ctx.stroke(r)
        }

        // 안내 텍스트 (top)
        let hint = "드래그로 민감 영역 박음 · Delete: 마지막 제거 · ESC/Return: 닫기"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let hintStr = NSAttributedString(string: hint, attributes: hintAttrs)
        let hintSize = hintStr.size()
        let hintBox = NSRect(
            x: (bounds.width - hintSize.width - 24) / 2,
            y: bounds.height - 50,
            width: hintSize.width + 24,
            height: hintSize.height + 14
        )
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
        ctx.fill(hintBox)
        hintStr.draw(at: NSPoint(x: hintBox.minX + 12, y: hintBox.minY + 7))
    }

    private func rect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}

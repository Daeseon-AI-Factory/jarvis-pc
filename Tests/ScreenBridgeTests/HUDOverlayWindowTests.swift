//
//  HUDOverlayWindowTests.swift
//  ScreenBridgeTests — Phase 5.0
//
//  NSWindow 본질 5개 lock — 누군가 toggle 추가하거나 hard rule 위반 시 fail.
//

import Testing
import AppKit
@testable import ScreenBridge

@Suite("HUDOverlayWindow")
@MainActor
struct HUDOverlayWindowTests {

    @Test("Layer 1 — transparent + hasShadow=false (회색 그림자 사각형 X)")
    func transparentNoShadow() {
        let w = HUDOverlayWindow()
        #expect(w.isOpaque == false)
        #expect(w.backgroundColor == NSColor.clear)
        #expect(w.hasShadow == false)
    }

    @Test("Layer 4 — ignoresMouseEvents=true 영구 (click-through, PR review reject toggle)")
    func clickThroughPermanent() {
        let w = HUDOverlayWindow()
        #expect(w.ignoresMouseEvents == true)
    }

    @Test("Layer 3 — level=.screenSaver (메뉴바/Dock 위)")
    func levelAboveAll() {
        let w = HUDOverlayWindow()
        #expect(w.level == NSWindow.Level.screenSaver)
    }

    @Test("Layer 7/8 — collectionBehavior 3개 셋 (canJoinAllSpaces + fullScreenAuxiliary + stationary)")
    func collectionBehaviorThreeBits() {
        let w = HUDOverlayWindow()
        #expect(w.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(w.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(w.collectionBehavior.contains(.stationary))
    }

    @Test("styleMask — borderless + nonactivatingPanel + fullSizeContentView")
    func styleMaskEssentials() {
        let w = HUDOverlayWindow()
        #expect(w.styleMask.contains(.borderless))
        #expect(w.styleMask.contains(.nonactivatingPanel))
        #expect(w.styleMask.contains(.fullSizeContentView))
    }

    @Test("focus 안 뺏음 — canBecomeKey/canBecomeMain false")
    func neverBecomesKey() {
        let w = HUDOverlayWindow()
        #expect(w.canBecomeKey == false)
        #expect(w.canBecomeMain == false)
    }

    @Test("sharingType=.none — 자기 캡처에 자기 HUD 안 들어감 (Phase 4.2 무한 루프 차단)")
    func notInOwnCapture() {
        let w = HUDOverlayWindow()
        #expect(w.sharingType == NSWindow.SharingType.none)
    }

    @Test("isReleasedWhenClosed=false — dismiss 후 instance 재사용 가능")
    func reusableAcrossDismiss() {
        let w = HUDOverlayWindow()
        #expect(w.isReleasedWhenClosed == false)
        #expect(w.hidesOnDeactivate == false)
    }
}

@Suite("HUDController")
@MainActor
struct HUDControllerTests {

    @Test("초기 isShowing=false")
    func initialNotShowing() {
        let c = HUDController()
        #expect(c.isShowing == false)
    }

    @Test("dismiss without present is no-op + isShowing 그대로 false")
    func dismissBeforePresentNoOp() {
        let c = HUDController()
        c.dismiss()
        #expect(c.isShowing == false)
    }
}

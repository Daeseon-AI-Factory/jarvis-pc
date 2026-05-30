//
//  BubblePositionerTests.swift
//  ScreenBridgeTests — Phase 5.x
//

import Testing
import CoreGraphics
@testable import ScreenBridge

@Suite("BubblePositioner")
struct BubblePositionerTests {

    private let screen = CGSize(width: 1440, height: 900)
    private let bubble = CGSize(width: 380, height: 88)

    @Test("bubble — 박스 아래에 공간 충분 시 박스 아래")
    func positionBelow() {
        let anchor = CGRect(x: 500, y: 200, width: 100, height: 50)
        let pos = BubblePositioner.position(
            anchorRect: anchor, bubbleSize: bubble, screenBounds: screen
        )
        // y: anchor.maxY (250) + verticalGap (16) + halfH (44) = 310
        #expect(pos.y == 310)
        // x: anchor.midX = 550 (clamping 안 됨)
        #expect(pos.x == 550)
    }

    @Test("bubble — 박스가 화면 하단 끝 시 박스 위로 (clamping)")
    func positionAboveWhenBelowNoSpace() {
        let anchor = CGRect(x: 500, y: 800, width: 100, height: 50)   // anchor.maxY = 850
        let pos = BubblePositioner.position(
            anchorRect: anchor, bubbleSize: bubble, screenBounds: screen
        )
        // yBelow = 850 + 16 + 44 = 910, yBelow + 44 = 954 > 900-12=888 → 위로
        // yAbove = 800 - 16 - 44 = 740
        #expect(pos.y == 740)
    }

    @Test("bubble — 박스 좌측 끝 (clamping left edge)")
    func clampLeft() {
        let anchor = CGRect(x: 0, y: 300, width: 60, height: 30)
        let pos = BubblePositioner.position(
            anchorRect: anchor, bubbleSize: bubble, screenBounds: screen
        )
        // anchor.midX = 30, halfW = 190, edge = 12 → clamped = 190+12 = 202
        #expect(pos.x == 202)
    }

    @Test("bubble — 박스 우측 끝 (clamping right edge)")
    func clampRight() {
        let anchor = CGRect(x: 1400, y: 300, width: 40, height: 30)
        let pos = BubblePositioner.position(
            anchorRect: anchor, bubbleSize: bubble, screenBounds: screen
        )
        // anchor.midX = 1420, screen.width - halfW - edge = 1440-190-12 = 1238
        #expect(pos.x == 1238)
    }

    @Test("bubble — 박스 우하단 코너 (둘 다 clamping)")
    func clampBottomRight() {
        let anchor = CGRect(x: 1400, y: 800, width: 40, height: 50)
        let pos = BubblePositioner.position(
            anchorRect: anchor, bubbleSize: bubble, screenBounds: screen
        )
        // X: right clamped → 1238
        // Y: yBelow = 850+16+44=910 > 888 → yAbove = 800-16-44=740
        #expect(pos.x == 1238)
        #expect(pos.y == 740)
    }

    @Test("bubble — 박스 정중앙 + 충분 공간 → 박스 아래 직접")
    func centeredCase() {
        let anchor = CGRect(x: 700, y: 400, width: 100, height: 60)
        let pos = BubblePositioner.position(
            anchorRect: anchor, bubbleSize: bubble, screenBounds: screen
        )
        // x = 750 (clamped 안 됨), y = 460+16+44=520
        #expect(pos.x == 750)
        #expect(pos.y == 520)
    }
}

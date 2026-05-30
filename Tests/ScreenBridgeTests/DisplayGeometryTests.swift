//
//  DisplayGeometryTests.swift
//  ScreenBridgeTests — Phase 3.1
//

import Testing
import CoreGraphics
import AppKit
@testable import ScreenBridge

@Suite("DisplayGeometry")
struct DisplayGeometryTests {

    @Test("Retina (scale 2.0) + 다운스케일 1568 — sent px → logical pt 4-layer 변환")
    func retinaDownscaledTransform() throws {
        // 시나리오: MacBook Pro 14 Retina display
        // - logical frame 1440x900 pt
        // - backingScaleFactor 2.0 → physical 2880x1800 px
        // - 다운스케일 maxDim 1568 → sent 1568x980 (긴 변 cap)
        let geom = DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            backingScaleFactor: 2.0,
            physicalSize: CGSize(width: 2880, height: 1800),
            sentSize: CGSize(width: 1568, height: 980)
        )

        // LLM 응답: sent px [100, 200, 300, 50]
        // sent → physical: x = 100 * (2880/1568) = 183.673..., w = 300 * (2880/1568) = 551.020...
        //                  y = 200 * (1800/980)  = 367.347..., h = 50  * (1800/980)  = 91.836...
        // physical → logical: ÷ 2.0
        //                  → (91.836, 183.673, 275.510, 45.918)
        let rect = try #require(geom.logicalRectFromSentBox([100, 200, 300, 50]))
        #expect(abs(rect.minX - 91.836) < 0.01)
        #expect(abs(rect.minY - 183.673) < 0.01)
        #expect(abs(rect.width - 275.510) < 0.01)
        #expect(abs(rect.height - 45.918) < 0.01)
    }

    @Test("HiDPI 없음 (scale 1.0) + 다운스케일 없음 — identity 변환")
    func identityTransformWhenNoScaling() throws {
        let geom = DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1024, height: 768),
            backingScaleFactor: 1.0,
            physicalSize: CGSize(width: 1024, height: 768),
            sentSize: CGSize(width: 1024, height: 768)
        )
        let rect = try #require(geom.logicalRectFromSentBox([100, 200, 300, 50]))
        #expect(rect.minX == 100)
        #expect(rect.minY == 200)
        #expect(rect.width == 300)
        #expect(rect.height == 50)
    }

    @Test("Retina (scale 2.0) + 다운스케일만 (physical==sent*scale)")
    func retinaOnlyNoExtraDownscale() throws {
        // sent == physical (다운스케일 없음 — 작은 display)
        let geom = DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 512, height: 384),
            backingScaleFactor: 2.0,
            physicalSize: CGSize(width: 1024, height: 768),
            sentSize: CGSize(width: 1024, height: 768)
        )
        // sent → physical: 1:1
        // physical → logical: ÷ 2.0
        let rect = try #require(geom.logicalRectFromSentBox([100, 200, 300, 50]))
        #expect(rect.minX == 50)
        #expect(rect.minY == 100)
        #expect(rect.width == 150)
        #expect(rect.height == 25)
    }

    @Test("box 길이 != 4 → nil")
    func invalidBoxReturnsNil() {
        let geom = DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1024, height: 768),
            backingScaleFactor: 1.0,
            physicalSize: CGSize(width: 1024, height: 768),
            sentSize: CGSize(width: 1024, height: 768)
        )
        #expect(geom.logicalRectFromSentBox([]) == nil)
        #expect(geom.logicalRectFromSentBox([1, 2, 3]) == nil)
        #expect(geom.logicalRectFromSentBox([1, 2, 3, 4, 5]) == nil)
    }

    @Test("0 division 방어 — sentSize 0이면 nil")
    func zeroSentSizeReturnsNil() {
        let geom = DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1024, height: 768),
            backingScaleFactor: 2.0,
            physicalSize: CGSize(width: 1024, height: 768),
            sentSize: CGSize(width: 0, height: 0)
        )
        #expect(geom.logicalRectFromSentBox([10, 20, 30, 40]) == nil)
    }

    @Test("globalAppKitRect — primary monitor (origin=0), top-left local → bottom-left global y-flip")
    func globalRectPrimaryMonitor() {
        let geom = DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            backingScaleFactor: 2.0,
            physicalSize: CGSize(width: 2880, height: 1800),
            sentSize: CGSize(width: 1440, height: 900)
        )
        // local top-left rect: (100, 200, 300, 50) → local maxY = 250
        // global bottom-left:  x = 0 + 100 = 100
        //                      y = 0 + (900 - 250) = 650
        //                      width/height 유지
        let global = geom.globalAppKitRect(fromLocalTopLeft: CGRect(x: 100, y: 200, width: 300, height: 50))
        #expect(global.minX == 100)
        #expect(global.minY == 650)
        #expect(global.width == 300)
        #expect(global.height == 50)
    }

    @Test("globalAppKitRect — 외부 monitor (origin.x=1440) — Tauri Layer 9 회피 핵심")
    func globalRectExternalMonitor() {
        // 외부 monitor가 primary 우측에. screen.frame.origin = (1440, 0).
        let geom = DisplayGeometry(
            displayID: 2,
            screenFrame: NSRect(x: 1440, y: 0, width: 1920, height: 1080),
            backingScaleFactor: 1.0,
            physicalSize: CGSize(width: 1920, height: 1080),
            sentSize: CGSize(width: 1568, height: 882)
        )
        // local top-left: (50, 100, 200, 40) → local maxY = 140
        // global: x = 1440 + 50 = 1490
        //         y = 0 + (1080 - 140) = 940
        let global = geom.globalAppKitRect(fromLocalTopLeft: CGRect(x: 50, y: 100, width: 200, height: 40))
        #expect(global.minX == 1490)  // 외부 monitor origin 반영 필수
        #expect(global.minY == 940)
        #expect(global.width == 200)
        #expect(global.height == 40)
    }

    @Test("globalAppKitRect — origin.y != 0 (위쪽 monitor — Vertical stack)")
    func globalRectStackedMonitor() {
        // 외부 monitor가 primary 위쪽 (MacBook Pro + 외부 27인치 위에 두기).
        let geom = DisplayGeometry(
            displayID: 2,
            screenFrame: NSRect(x: 0, y: 900, width: 2560, height: 1440),
            backingScaleFactor: 2.0,
            physicalSize: CGSize(width: 5120, height: 2880),
            sentSize: CGSize(width: 1568, height: 882)
        )
        // local top-left: (10, 20, 100, 30) → local maxY = 50
        // global: x = 0 + 10 = 10
        //         y = 900 + (1440 - 50) = 900 + 1390 = 2290
        let global = geom.globalAppKitRect(fromLocalTopLeft: CGRect(x: 10, y: 20, width: 100, height: 30))
        #expect(global.minX == 10)
        #expect(global.minY == 2290)
    }

    @Test("비균일 scaleX/scaleY — 3024x1964 → 1568x1018 (M3 14-inch 다운스케일 rounding)")
    func nonUniformScale() throws {
        // M3 14" 실 시나리오: 3024x1964 physical → 1568x1018 sent (rounding로 비균일).
        // scaleX = 3024/1568 ≈ 1.92857
        // scaleY = 1964/1018 ≈ 1.92927
        // 둘이 약 0.04% 다름 — 코드가 단일 ratio로 collapse하지 않고 분리 처리 confirm.
        let geom = DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            backingScaleFactor: 2.0,
            physicalSize: CGSize(width: 3024, height: 1964),
            sentSize: CGSize(width: 1568, height: 1018)
        )
        // 대각선 box [0, 0, 100, 100] sent — scaleX vs scaleY 분리 검증
        let rect = try #require(geom.logicalRectFromSentBox([0, 0, 100, 100]))
        let expectedW = 100.0 * (3024.0 / 1568.0) / 2.0   // ≈ 96.4286
        let expectedH = 100.0 * (1964.0 / 1018.0) / 2.0   // ≈ 96.4637
        #expect(abs(rect.width - expectedW) < 0.01)
        #expect(abs(rect.height - expectedH) < 0.01)
        // 핵심: width != height (비균일 scale lock-in)
        #expect(rect.width != rect.height)
    }
}

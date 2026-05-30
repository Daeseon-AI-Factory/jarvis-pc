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
}

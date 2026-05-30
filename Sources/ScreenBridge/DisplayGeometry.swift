//
//  DisplayGeometry.swift
//  ScreenBridge — Phase 3.1
//
//  4-layer 좌표 변환 캡슐화. Tauri Layer 6 (DPR 4-layer 누수) 재발 방지.
//
//  Layer 1. physical px   — ScreenCaptureKit이 반환한 원본 픽셀 (Retina 2x/3x scale).
//  Layer 2. sent px       — LLM에 보낸 다운스케일 이미지 픽셀 (≤ 1568).
//  Layer 3. logical pt    — AppKit/NSScreen 좌표 (HUD overlay window 좌표계).
//  Layer 4. screen-local pt — NSScreen origin 기준 (HUD frame.origin 보정).
//
//  LLM은 sent px 좌표 [x, y, w, h]로 응답 — `logicalRectFromSentBox`가 logical pt 변환.
//  좌표계: top-left origin (UI 좌표 — SwiftUI/CoreGraphics drawing 일치). NSWindow는
//  bottom-left이라 Phase 5 HUD에서 NSScreen.frame 기준 한 번 더 flip 필요.
//
//  ⚠️ `NSScreen.main` 절대 금지 — 항상 captured display 기준 (Tauri Layer 9 회피).
//

import AppKit
import CoreGraphics

struct DisplayGeometry: Sendable {
    let displayID: CGDirectDisplayID
    let screenFrame: NSRect             // logical pt, 전역 (bottom-left origin in AppKit)
    let backingScaleFactor: CGFloat     // Retina 2.0 / non-Retina 1.0 / Studio 3.0 등
    let physicalSize: CGSize            // captured PNG의 원본 px
    let sentSize: CGSize                // LLM에 보낸 다운스케일 PNG px (≤ 1568)

    /// LLM sent px 좌표 → screen-local logical pt CGRect (top-left origin, UI 좌표).
    /// **주의**: 이 값은 *NSScreen 기준 local* — 외부 monitor (screenFrame.origin != 0)에선
    /// 그대로 `NSWindow.setFrame(_:)` 호출 X. 반드시 `globalAppKitRect(fromLocalTopLeft:)`로
    /// 전역 bottom-left AppKit 좌표로 변환 후 사용. Phase 5 HUD code 강제.
    func logicalRectFromSentBox(_ box: [Int]) -> CGRect? {
        guard box.count == 4 else { return nil }
        guard sentSize.width > 0, sentSize.height > 0, backingScaleFactor > 0 else { return nil }

        // sent → physical 비례
        let scaleX = physicalSize.width / sentSize.width
        let scaleY = physicalSize.height / sentSize.height
        let physX = CGFloat(box[0]) * scaleX
        let physY = CGFloat(box[1]) * scaleY
        let physW = CGFloat(box[2]) * scaleX
        let physH = CGFloat(box[3]) * scaleY

        // physical px → logical pt (backingScaleFactor 나눔)
        let lx = physX / backingScaleFactor
        let ly = physY / backingScaleFactor
        let lw = physW / backingScaleFactor
        let lh = physH / backingScaleFactor

        return CGRect(x: lx, y: ly, width: lw, height: lh)
    }

    /// Screen-local top-left CGRect → 전역 AppKit (bottom-left global) NSRect.
    /// HUD overlay `NSWindow.setFrame(_:)` 에 그대로 사용 가능.
    ///
    /// 두 가지 변환 한 곳:
    /// 1. **origin add**: screenFrame.origin (외부 monitor x=1440 등) 더하기.
    /// 2. **y flip**: NSScreen은 bottom-left이라 `screenFrame.maxY - local.maxY`.
    ///
    /// Tauri Layer 9 재발 차단 — Phase 5 HUD code가 raw CGRect를 NSWindow에 직접 못 박게.
    func globalAppKitRect(fromLocalTopLeft local: CGRect) -> NSRect {
        NSRect(
            x: screenFrame.origin.x + local.origin.x,
            y: screenFrame.origin.y + (screenFrame.height - (local.origin.y + local.height)),
            width: local.width,
            height: local.height
        )
    }

    /// captured display의 NSScreen 다시 찾기 (해상도 변경/hotplug 대응).
    /// nil이면 HUD overlay 띄울 곳 없음 — caller가 dismiss + 사용자 friendly 메시지.
    @MainActor
    var currentScreen: NSScreen? {
        NSScreen.screens.first {
            let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            return id == displayID
        }
    }
}

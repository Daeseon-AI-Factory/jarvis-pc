//
//  AXElement.swift
//  ScreenBridge — Phase 6.2
//
//  macOS Accessibility tree에서 추출한 clickable element 정보.
//  `rectInLogicalPt`는 이미 logical pt screen-global — DisplayGeometry 변환 불필요.
//  OCR이 visible text만 잡는 한계 보완 — Dock 아이콘 / icon-only 버튼 / 이미지 메뉴 deterministic.
//

import CoreGraphics
import Foundation

struct AXElement: Sendable, Equatable {
    /// AXTitle + AXDescription + AXValue 합본 (non-empty만, space로 join).
    /// `target_text`와 매칭할 source.
    let text: String

    /// Screen-global logical pt CGRect (top-left origin per AppKit 표준은 X — Accessibility는
    /// *global top-left*가 표준). HUDAnnotation에 그대로 사용 가능 (`globalAppKitRect` 변환
    /// 불필요 — Accessibility는 이미 global).
    ///
    /// ⚠️ 주의: macOS Accessibility API의 AXPosition은 **global top-left** (window manager
    /// 좌표 = bottom-left이지만 AX는 항상 top-left). HUDOverlayWindow.setFrame은 bottom-left
    /// 받음 — Phase 5.x bubble 작성 시 별도 변환 필요할 수도.
    let rectInLogicalPt: CGRect

    /// AXButton, AXDockItem, AXLink, AXMenuItem 등.
    let role: String

    /// 어느 앱의 element (디버그/log용).
    let appName: String?
}

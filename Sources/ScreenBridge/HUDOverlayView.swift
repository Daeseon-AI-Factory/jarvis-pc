//
//  HUDOverlayView.swift
//  ScreenBridge — Phase 5.0
//
//  HUD overlay 위 SwiftUI 렌더. screen-local top-left 좌표 시스템 (SwiftUI 표준).
//  HUDOverlayWindow의 frame이 screen.frame과 1:1 — annotation.rect 좌표 그대로.
//  Phase 5.x에서 bubble + 한글 next_action 추가.
//

import SwiftUI

/// 단일 빨간 박스 (+향후 bubble) annotation.
/// `rect`는 screen-local top-left logical pt — `DisplayGeometry.logicalRectFromSentBox` 결과.
struct HUDAnnotation: Sendable, Equatable {
    let rect: CGRect

    init(rect: CGRect) {
        self.rect = rect
    }
}

struct HUDOverlayView: View {
    let annotation: HUDAnnotation

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 투명 배경 — SwiftUI hit-test가 ignoresMouseEvents=true 우회 못 하게.
            Color.clear

            // 빨간 박스 — 두께 3pt, 코너 4pt (안경 메타포: 사용자 눈에 박힘).
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.red, lineWidth: 3)
                .frame(width: annotation.rect.width, height: annotation.rect.height)
                .position(
                    x: annotation.rect.midX,
                    y: annotation.rect.midY
                )
        }
        .ignoresSafeArea()
    }
}

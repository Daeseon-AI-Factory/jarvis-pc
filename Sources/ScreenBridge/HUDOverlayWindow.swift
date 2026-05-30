//
//  HUDOverlayWindow.swift
//  ScreenBridge — Phase 5.0
//
//  화면 위 click-through transparent NSPanel — *안경 메타포의 유리알*.
//  Tauri 16 layer 중 1/4/7/8/9 회피 5개 본질:
//
//    1. transparent + 그림자 없음 (Layer 1) — isOpaque=false, .clear, hasShadow=false
//    2. click-through 영구 (Layer 4) — ignoresMouseEvents=true. mouse 클릭 desktop으로 통과.
//    3. level=.screenSaver — 메뉴바/Dock 위까지 덮음
//    4. collectionBehavior 3개 셋 (Layer 7/8) — Keynote 풀스크린/Mission Control/Stage Manager에서도 유지
//    5. captured display NSScreen에 frame pin (Layer 9) — HUDController.present(on:) 강제
//
//  Phase 5.x에서 NSHostingView<HUDOverlayView> 임베드. Phase 5.0은 hardcode 빨간 박스 1개.
//

import AppKit

@MainActor
final class HUDOverlayWindow: NSPanel {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Layer 1 — transparent + 그림자 X
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false

        // Layer 3 — 메뉴바/Dock 위
        self.level = .screenSaver

        // Layer 7/8 — 풀스크린 + 모든 Space + 자기 Space 고정 (Mission Control에서 안 옮김)
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]

        // Layer 4 — 영구 click-through. ⚠️ toggle 추가 금지 (PR review reject).
        self.ignoresMouseEvents = true

        // ScreenCaptureKit 다른 client에서 안 보임 — Phase 4.2에서 자기 화면 캡처 시
        // 자기 HUD overlay 같이 캡처되는 무한 루프 차단.
        self.sharingType = .none

        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
    }

    // focus 절대 안 뺏음 — 사용자가 본 앱 그대로 키보드 입력 가능.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

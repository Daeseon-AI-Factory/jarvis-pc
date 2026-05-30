//
//  HUDOverlayView.swift
//  ScreenBridge — Phase 4.2 (rewrite from 5.0)
//
//  HUDContent 3 case: loading / annotated / error. case별 SwiftUI 분기.
//  screen-local top-left 좌표 (annotation), 화면 중앙 pill (loading/error).
//

import SwiftUI

struct HUDAnnotation: Sendable, Equatable {
    let rect: CGRect

    init(rect: CGRect) {
        self.rect = rect
    }
}

enum HUDContent: Sendable, Equatable {
    case loading(message: String)
    case annotated(HUDAnnotation)
    case error(message: String)
}

struct HUDOverlayView: View {
    let content: HUDContent

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 투명 배경 — click-through 영역.
            Color.clear

            switch content {
            case .loading(let message):
                LoadingPill(message: message)
            case .annotated(let ann):
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red, lineWidth: 3)
                    .frame(width: ann.rect.width, height: ann.rect.height)
                    .position(x: ann.rect.midX, y: ann.rect.midY)
            case .error(let message):
                ErrorPill(message: message)
            }
        }
        .ignoresSafeArea()
    }
}

private struct LoadingPill: View {
    let message: String
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
            Text(message)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.black.opacity(0.75), in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct ErrorPill: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.headline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

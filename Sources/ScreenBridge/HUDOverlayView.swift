//
//  HUDOverlayView.swift
//  ScreenBridge — Phase 5.x bubble
//
//  HUDContent 3 case: loading / annotated / error.
//  annotated는 빨간 박스 + 한글 next_action bubble + sourceTag (OCR/AX:role).
//  화면 가장자리 clamping — 박스가 우/하단 끝이면 bubble 좌측/위로.
//

import SwiftUI

struct HUDAnnotation: Sendable, Equatable {
    let rect: CGRect
    let nextAction: String      // 한글 친화 next_action (Phase 5.x)
    let sourceTag: String       // "OCR" / "AX:AXDockItem" / "LLM" (디버그 + 신뢰)

    init(rect: CGRect, nextAction: String = "", sourceTag: String = "") {
        self.rect = rect
        self.nextAction = nextAction
        self.sourceTag = sourceTag
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
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 투명 배경 — click-through 영역
                Color.clear

                switch content {
                case .loading(let message):
                    LoadingPill(message: message)
                case .annotated(let ann):
                    BoxAndBubble(annotation: ann, screenBounds: geo.size)
                case .error(let message):
                    ErrorPill(message: message)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Annotated (빨간 박스 + bubble)

private struct BoxAndBubble: View {
    let annotation: HUDAnnotation
    let screenBounds: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 빨간 박스 — 안경 메타포의 *유리알*
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.red, lineWidth: 3)
                .frame(width: annotation.rect.width, height: annotation.rect.height)
                .position(x: annotation.rect.midX, y: annotation.rect.midY)

            // 한글 bubble — next_action 있을 때만
            if !annotation.nextAction.isEmpty {
                BubbleView(annotation: annotation, screenBounds: screenBounds)
            }
        }
    }
}

private struct BubbleView: View {
    let annotation: HUDAnnotation
    let screenBounds: CGSize

    private static let estimatedSize = CGSize(width: 380, height: 88)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(annotation.nextAction)
                .font(.title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !annotation.sourceTag.isEmpty {
                Text("[\(annotation.sourceTag)]")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: Self.estimatedSize.width)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .position(BubblePositioner.position(
            anchorRect: annotation.rect,
            bubbleSize: Self.estimatedSize,
            screenBounds: screenBounds
        ))
    }
}

/// Bubble anchor 위치 계산 — 화면 가장자리 clamping.
/// 기본: 박스 아래. 박스가 화면 하단 끝이면 위로. 박스 좌우 끝이면 가장자리 따라 clamping.
enum BubblePositioner {
    static let verticalGap: CGFloat = 16
    static let edgePadding: CGFloat = 12

    static func position(
        anchorRect: CGRect,
        bubbleSize: CGSize,
        screenBounds: CGSize
    ) -> CGPoint {
        let halfW = bubbleSize.width / 2
        let halfH = bubbleSize.height / 2

        // X: anchor.midX 기본, 좌/우 가장자리 clamping
        let preferredX = anchorRect.midX
        let clampedX = max(
            halfW + edgePadding,
            min(screenBounds.width - halfW - edgePadding, preferredX)
        )

        // Y: 박스 아래 기본, 공간 부족 시 위로
        let yBelow = anchorRect.maxY + verticalGap + halfH
        let yAbove = anchorRect.minY - verticalGap - halfH

        let clampedY: CGFloat
        if yBelow + halfH > screenBounds.height - edgePadding {
            // 아래 부족 → 위로 (위도 부족하면 최소 padding 보장)
            clampedY = max(halfH + edgePadding, yAbove)
        } else {
            clampedY = yBelow
        }

        return CGPoint(x: clampedX, y: clampedY)
    }
}

// MARK: - Loading / Error pills (Phase 4.2)

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

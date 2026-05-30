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
    let alternatives: [Alternative]   // 2번/3번 후보 (multi-target overlay)

    /// 보조 후보. 회색 dashed 박스 + 번호 라벨로 표시.
    struct Alternative: Sendable, Equatable {
        let rect: CGRect
        let sourceTag: String
        let number: Int       // 2, 3, ...
    }

    init(rect: CGRect, nextAction: String = "", sourceTag: String = "", alternatives: [Alternative] = []) {
        self.rect = rect
        self.nextAction = nextAction
        self.sourceTag = sourceTag
        self.alternatives = alternatives
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
            // Primary 빨간 박스 — 1번 (가장 likely)
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.red, lineWidth: 3)
                .frame(width: annotation.rect.width, height: annotation.rect.height)
                .position(x: annotation.rect.midX, y: annotation.rect.midY)

            // Primary 번호 라벨 "1" — 다중 후보면 표시
            if !annotation.alternatives.isEmpty {
                NumberBadge(number: 1, color: .red)
                    .position(
                        x: annotation.rect.minX - 14,
                        y: annotation.rect.minY - 14
                    )
            }

            // Alternative 회색 dashed 박스 + 번호 — *user-in-the-loop* (사용자가 선택)
            ForEach(Array(annotation.alternatives.enumerated()), id: \.offset) { _, alt in
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        Color.gray.opacity(0.75),
                        style: StrokeStyle(lineWidth: 2.5, dash: [6, 4])
                    )
                    .frame(width: alt.rect.width, height: alt.rect.height)
                    .position(x: alt.rect.midX, y: alt.rect.midY)

                NumberBadge(number: alt.number, color: .gray)
                    .position(
                        x: alt.rect.minX - 14,
                        y: alt.rect.minY - 14
                    )
            }

            // 한글 bubble — next_action 있을 때만
            if !annotation.nextAction.isEmpty {
                BubbleView(annotation: annotation, screenBounds: screenBounds)
            }
        }
    }
}

/// 번호 라벨 (박스 좌상단 코너). 빨강 = primary, 회색 = alternative.
private struct NumberBadge: View {
    let number: Int
    let color: Color

    var body: some View {
        Text("\(number)")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(color))
            .shadow(color: .black.opacity(0.3), radius: 2)
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

            // Alternative 안내 — "또는 2번도 가능" (사용자 선택 권한)
            if !annotation.alternatives.isEmpty {
                Text("또는 2번 (회색)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

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

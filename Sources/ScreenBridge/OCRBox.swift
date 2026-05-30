//
//  OCRBox.swift
//  ScreenBridge — Phase 6.1
//
//  Vision OCR 결과 한 텍스트 박스. `rectInSentImage`는 sent image px (다운스케일된
//  이미지 좌표, top-left origin) — `ElementMatcher`가 `DisplayGeometry.logicalRectFromSentBox`로
//  screen-local logical pt 변환.
//

import CoreGraphics
import Foundation

struct OCRBox: Sendable, Equatable {
    let text: String
    let rectInSentImage: CGRect    // sent image 좌표 px, top-left origin
    let confidence: Float           // 0.0-1.0
}

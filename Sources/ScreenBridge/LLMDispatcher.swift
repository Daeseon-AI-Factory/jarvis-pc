//
//  LLMDispatcher.swift
//  ScreenBridge — Phase 2.3
//
//  Vision + 추상 지시 → AnalysisResult 변환 contract.
//

import CoreGraphics
import Foundation

protocol LLMDispatcher: Sendable {
    /// 사용자가 본 화면 PNG + 사용자가 받은 추상 지시 → 화면 위 구체 동작.
    /// `imageSize`는 원본 캡처 크기 (다운스케일 후의 sent size). dispatcher는 안 줄이고 보냄.
    func analyze(
        imageData: Data,
        imageSize: CGSize,
        instruction: String
    ) async throws -> AnalysisResult
}

/// Dispatcher 단계 에러. Phase 4.2에서 한국어 사용자 facing 메시지로 매핑.
enum DispatcherError: Error, Sendable {
    case missingAPIKey
    case network(URLError)
    case httpStatus(Int, body: String)
    case decoding(String)
    case maxTokens
    case invalidResponse(String)
    case retriesExhausted(lastStatus: Int)
}

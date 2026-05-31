//
//  FallbackDispatcher.swift
//  ScreenBridge — Phase 7.2
//
//  Primary (Gemini) + fallback (Claude) wrapper. primary가 429/quota error 시
//  자동 Claude swap → 사용자 *unblock*. 단일 LLMDispatcher protocol 유지 — caller 무관.
//
//  결정 (DECISIONS): 429 retriesExhausted 시 swap. 다른 error (network/decoding 등)는
//  swap 안 함 (primary code path bug 가능성). Claude도 429면 *둘 다 fail* (사용자 알림).
//

import CoreGraphics
import Foundation

actor FallbackDispatcher: LLMDispatcher {
    private let primary: LLMDispatcher
    private let fallback: LLMDispatcher
    private let primaryName: String
    private let fallbackName: String

    init(
        primary: LLMDispatcher, primaryName: String = "gemini",
        fallback: LLMDispatcher, fallbackName: String = "claude"
    ) {
        self.primary = primary
        self.fallback = fallback
        self.primaryName = primaryName
        self.fallbackName = fallbackName
    }

    func analyze(
        imageData: Data,
        imageSize: CGSize,
        instruction: String
    ) async throws -> AnalysisResult {
        do {
            return try await primary.analyze(
                imageData: imageData, imageSize: imageSize, instruction: instruction
            )
        } catch let err as DispatcherError {
            // 429 / quota exhausted → swap. 다른 error는 throw 그대로 (primary bug 가능성).
            guard Self.shouldFallback(on: err) else {
                Log.dispatcher.notice("[fallback] primary error not swappable (\(String(describing: err), privacy: .public)) — throw")
                throw err
            }
            Log.dispatcher.info("[fallback] \(self.primaryName, privacy: .public) → \(self.fallbackName, privacy: .public) swap (primary 429/quota)")
            do {
                return try await fallback.analyze(
                    imageData: imageData, imageSize: imageSize, instruction: instruction
                )
            } catch {
                Log.dispatcher.error("[fallback] \(self.fallbackName, privacy: .public) 도 fail: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    /// Prewarm은 *둘 다*. primary는 첫 호출 cold 줄이고, fallback은 swap 시점 빠른 응답.
    func prewarm() async {
        await primary.prewarm()
        await fallback.prewarm()
    }

    /// 어떤 DispatcherError가 fallback 호출 trigger하나.
    /// - 429 retriesExhausted: quota — 다른 vendor 시도 의미 있음
    /// - httpStatus 429: 동일
    /// - 그 외: throw (primary fix 필요 신호)
    static func shouldFallback(on error: DispatcherError) -> Bool {
        switch error {
        case .retriesExhausted(let lastStatus) where lastStatus == 429:
            return true
        case .httpStatus(let code, _) where code == 429:
            return true
        default:
            return false
        }
    }
}

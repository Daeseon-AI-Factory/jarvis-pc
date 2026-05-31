//
//  FallbackDispatcherTests.swift
//  ScreenBridgeTests — Phase 7.2
//
//  FallbackDispatcher swap logic + 결정 rule:
//  - primary 429 → fallback 호출
//  - primary 다른 error → throw (swap 안 함)
//  - fallback도 fail → throw
//

import CoreGraphics
import Foundation
import Testing
@testable import ScreenBridge

@Suite("Phase 7.2 — FallbackDispatcher.shouldFallback")
struct FallbackShouldFallbackTests {

    @Test("retriesExhausted(429) → swap")
    func retriesExhausted429() {
        #expect(FallbackDispatcher.shouldFallback(on: .retriesExhausted(lastStatus: 429)) == true)
    }

    @Test("retriesExhausted(500) → throw (no swap)")
    func retriesExhausted500() {
        #expect(FallbackDispatcher.shouldFallback(on: .retriesExhausted(lastStatus: 500)) == false)
    }

    @Test("httpStatus(429) → swap")
    func httpStatus429() {
        #expect(FallbackDispatcher.shouldFallback(on: .httpStatus(429, body: "")) == true)
    }

    @Test("httpStatus(401) → throw (key invalid, swap 무의미)")
    func httpStatus401() {
        #expect(FallbackDispatcher.shouldFallback(on: .httpStatus(401, body: "")) == false)
    }

    @Test("missingAPIKey → throw")
    func missingAPIKey() {
        #expect(FallbackDispatcher.shouldFallback(on: .missingAPIKey) == false)
    }

    @Test("decoding → throw (primary bug 가능성)")
    func decoding() {
        #expect(FallbackDispatcher.shouldFallback(on: .decoding("bad json")) == false)
    }

    @Test("invalidResponse → throw")
    func invalidResponse() {
        #expect(FallbackDispatcher.shouldFallback(on: .invalidResponse("no candidates")) == false)
    }
}

@Suite("Phase 7.2 — FallbackDispatcher analyze swap behavior")
struct FallbackAnalyzeTests {

    @Test("primary 429 → fallback 호출 + fallback 응답 return")
    func primary429FallbackOk() async throws {
        let primary = StubDispatcher(behavior: .fail(.retriesExhausted(lastStatus: 429)))
        let fallback = StubDispatcher(behavior: .succeed(targetText: "FallbackChrome"))
        let wrap = FallbackDispatcher(primary: primary, fallback: fallback)
        let result = try await wrap.analyze(
            imageData: Data(), imageSize: CGSize(width: 100, height: 100), instruction: "test"
        )
        #expect(result.targetText == "FallbackChrome")
    }

    @Test("primary 500 → throw (swap 안 함)")
    func primary500NoSwap() async {
        let primary = StubDispatcher(behavior: .fail(.retriesExhausted(lastStatus: 500)))
        let fallback = StubDispatcher(behavior: .succeed(targetText: "Should-not-reach"))
        let wrap = FallbackDispatcher(primary: primary, fallback: fallback)
        do {
            _ = try await wrap.analyze(
                imageData: Data(), imageSize: CGSize(width: 100, height: 100), instruction: "test"
            )
            Issue.record("expected throw")
        } catch {
            // OK — primary's 500 propagates
        }
    }

    @Test("primary 429 + fallback도 429 → throw (둘 다 막힘)")
    func bothFail() async {
        let primary = StubDispatcher(behavior: .fail(.retriesExhausted(lastStatus: 429)))
        let fallback = StubDispatcher(behavior: .fail(.retriesExhausted(lastStatus: 429)))
        let wrap = FallbackDispatcher(primary: primary, fallback: fallback)
        do {
            _ = try await wrap.analyze(
                imageData: Data(), imageSize: CGSize(width: 100, height: 100), instruction: "test"
            )
            Issue.record("expected throw when both fail")
        } catch {
            // OK
        }
    }

    @Test("primary 성공 → fallback 안 부름")
    func primaryOk() async throws {
        let primary = StubDispatcher(behavior: .succeed(targetText: "PrimaryChrome"))
        let fallback = StubDispatcher(behavior: .succeed(targetText: "Should-not-reach"))
        let wrap = FallbackDispatcher(primary: primary, fallback: fallback)
        let result = try await wrap.analyze(
            imageData: Data(), imageSize: CGSize(width: 100, height: 100), instruction: "test"
        )
        #expect(result.targetText == "PrimaryChrome")
    }
}

/// Test용 stub — succeed (지정 targetText) 또는 fail (지정 error).
private final class StubDispatcher: LLMDispatcher, @unchecked Sendable {
    enum Behavior {
        case succeed(targetText: String)
        case fail(DispatcherError)
    }
    let behavior: Behavior

    init(behavior: Behavior) { self.behavior = behavior }

    func analyze(imageData: Data, imageSize: CGSize, instruction: String) async throws -> AnalysisResult {
        switch behavior {
        case .succeed(let txt):
            return AnalysisResult(
                screenState: "test screen",
                nextAction: "tap \(txt)",
                targetText: txt,
                reasoning: "stub"
            )
        case .fail(let err):
            throw err
        }
    }
}

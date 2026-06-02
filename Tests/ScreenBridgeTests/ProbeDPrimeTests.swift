//
//  ProbeDPrimeTests.swift
//  ScreenBridgeTests — Phase 9.0 Week 1 GO/NO-GO
//
//  Qwen2.5-VL-3B vs Gemini 2.5 Flash accuracy 측정. 5 fixture가 박혀있을 때만 실행.
//
//  실행:
//    1. fixtures/sensitive_screens/*.png 박음 (사용자 본인 환경)
//    2. .env에 GEMINI_API_KEY + (선택) ANTHROPIC_API_KEY 박음
//    3. ./dev.sh로 *최소 한 번 실행* — Qwen ~2GB HF download
//    4. RUN_PROBE_D_PRIME=1 swift test --filter ProbeDPrime
//
//  GO/NO-GO criteria:
//    ≥ 80% top-1 hit rate (4/5 fixtures) → Phase 9.0 진행
//    70-80% (3-4/5) → 다른 model 평가 (Gemma 3 / InternVL)
//    < 70% (≤2/5) → cloud fallback (SCREENBRIDGE_USE_LOCAL X 영구)
//

import Foundation
import Testing
@testable import ScreenBridge

@Suite("Phase 9.0 — Probe D-prime scaffold")
struct ProbeDPrimeTests {

    /// fixtures/sensitive_screens/instructions.json 박혀있어야 실행.
    /// instructions.json: 박힌 README.md 참고 (사용자 본인 5 screenshot 박는 방법).
    @Test("fixtures directory + instructions.json 박혀있나")
    func fixturesExist() throws {
        let path = Self.fixturesDir.appendingPathComponent("instructions.json")
        if !FileManager.default.fileExists(atPath: path.path) {
            // Skip gracefully — 사용자가 fixtures 박지 않았으면 OK.
            print("[probe-d-prime] skip — fixtures/sensitive_screens/instructions.json 박지 X")
            return
        }
        let data = try Data(contentsOf: path)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let fixtures = json?["fixtures"] as? [[String: Any]] ?? []
        #expect(fixtures.count == 5)
    }

    /// 사용자가 RUN_PROBE_D_PRIME=1 + fixtures 박은 후만 실행. CI에선 skip.
    @Test("Qwen vs Gemini accuracy 측정 (RUN_PROBE_D_PRIME=1 시만)")
    func probeAccuracy() async throws {
        guard ProcessInfo.processInfo.environment["RUN_PROBE_D_PRIME"] == "1" else {
            print("[probe-d-prime] skip — RUN_PROBE_D_PRIME=1 박지 X")
            return
        }
        guard FileManager.default.fileExists(atPath: Self.fixturesDir.path) else {
            print("[probe-d-prime] skip — fixtures dir 박지 X")
            return
        }

        let instructionsURL = Self.fixturesDir.appendingPathComponent("instructions.json")
        guard FileManager.default.fileExists(atPath: instructionsURL.path) else {
            print("[probe-d-prime] skip — instructions.json 박지 X")
            return
        }

        let data = try Data(contentsOf: instructionsURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let fixtures = json?["fixtures"] as? [[String: Any]] ?? []

        var geminiHits = 0
        var qwenHits = 0
        var attempted = 0

        for fixture in fixtures {
            guard let id = fixture["id"] as? String,
                  let instruction = fixture["instruction"] as? String,
                  let expectedTarget = fixture["expectedTarget"] as? String else { continue }

            let imageURL = Self.fixturesDir.appendingPathComponent("\(id).png")
            guard let imageData = try? Data(contentsOf: imageURL) else {
                print("[probe-d-prime] skip — \(id).png 박지 X")
                continue
            }

            attempted += 1

            // Gemini side
            if let gemini = GeminiDispatcher.fromEnvironment() {
                do {
                    let result = try await gemini.analyze(
                        imageData: imageData,
                        imageSize: CGSize(width: 1024, height: 768),
                        instruction: instruction
                    )
                    if result.targetText.localizedCaseInsensitiveContains(expectedTarget) {
                        geminiHits += 1
                        print("[probe-d-prime] gemini ✓ \(id) → \(result.targetText)")
                    } else {
                        print("[probe-d-prime] gemini ✗ \(id) → \(result.targetText) (expected \(expectedTarget))")
                    }
                } catch {
                    print("[probe-d-prime] gemini error \(id): \(error)")
                }
            }

            // Qwen side — first launch downloads ~2GB
            let qwen = QwenLocalDispatcher.make()
            do {
                let result = try await qwen.analyze(
                    imageData: imageData,
                    imageSize: CGSize(width: 1024, height: 768),
                    instruction: instruction
                )
                if result.targetText.localizedCaseInsensitiveContains(expectedTarget) {
                    qwenHits += 1
                    print("[probe-d-prime] qwen ✓ \(id) → \(result.targetText)")
                } else {
                    print("[probe-d-prime] qwen ✗ \(id) → \(result.targetText) (expected \(expectedTarget))")
                }
            } catch {
                print("[probe-d-prime] qwen error \(id): \(error)")
            }
        }

        guard attempted > 0 else {
            print("[probe-d-prime] no fixtures attempted")
            return
        }

        let geminiRate = Double(geminiHits) / Double(attempted)
        let qwenRate = Double(qwenHits) / Double(attempted)

        print("[probe-d-prime] ============================================")
        print("[probe-d-prime] Gemini: \(geminiHits)/\(attempted) (\(Int(geminiRate * 100))%)")
        print("[probe-d-prime] Qwen:   \(qwenHits)/\(attempted) (\(Int(qwenRate * 100))%)")
        print("[probe-d-prime] ============================================")
        print("[probe-d-prime] GO/NO-GO:")
        if qwenRate >= 0.8 {
            print("[probe-d-prime] ✅ GO — Phase 9.0 진행")
        } else if qwenRate >= 0.7 {
            print("[probe-d-prime] ⚠️ 다른 model 평가 (Gemma 3 / InternVL)")
        } else {
            print("[probe-d-prime] ❌ fallback — cloud Gemini 영구")
        }
        print("[probe-d-prime] ============================================")
    }

    // MARK: - Helpers

    private static var fixturesDir: URL {
        // Tests/ScreenBridgeTests/ → ../../fixtures/sensitive_screens/
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures")
            .appendingPathComponent("sensitive_screens")
    }
}

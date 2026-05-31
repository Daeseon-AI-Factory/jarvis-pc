//
//  SecretMaskerTests.swift
//  ScreenBridgeTests — v0.2 (보안 layer 1번)
//
//  *Test fixture warning*: 모든 fake token은 *split + join*으로 박음.
//  source code에 *full token literal* 박지 않음 → GitHub push protection /
//  secret scanner false-positive 차단. fake values는 *명백히* fixture (FAKE/FIXTURE).
//

import Foundation
import Testing
@testable import ScreenBridge

// MARK: - Fake fixtures (split to avoid push protection false-positive)

private enum Fixture {
    // Pattern 매칭 위해 alphanumeric only (regex sk-[a-zA-Z0-9]{20,} 등).
    // GitHub push protection 회피 위해 split + dynamic (소스에 full token literal X).
    static let openaiKey = "sk" + "-" + String(repeating: "F", count: 30)
    static let anthropicKey = "sk-" + "ant" + "-" + String(repeating: "F", count: 30)
    static let googleKey = "AI" + "za" + String(repeating: "F", count: 35)
    static let awsKey = "AK" + "IA" + String(repeating: "F", count: 16)
    static let githubPatNew = "github_" + "pat_" + String(repeating: "F", count: 82)
    static let githubClassic = "ghp" + "_" + String(repeating: "F", count: 36)
    static let slackToken = "xox" + "b" + "-" + String(repeating: "F", count: 20)
}

@Suite("v0.2 — SecretMasker.mask")
struct SecretMaskerMaskTests {

    @Test("OpenAI key — sk- prefix")
    func openaiKey() {
        let input = "API key는 \(Fixture.openaiKey) 이거예요"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:openai-key]"))
        #expect(!result.contains(Fixture.openaiKey))
    }

    @Test("Anthropic key — sk-ant- prefix (specific 우선)")
    func anthropicKey() {
        let input = "Claude는 \(Fixture.anthropicKey) 이거"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:anthropic-key]"))
        #expect(!result.contains(Fixture.anthropicKey))
    }

    @Test("Google AI Studio (Gemini) key — AIza prefix")
    func googleKey() {
        let input = "Gemini key: \(Fixture.googleKey)"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:google-key]"))
    }

    @Test("AWS access key — AKIA prefix")
    func awsKey() {
        let input = "AWS는 \(Fixture.awsKey) 이거 사용"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:aws-access-key]"))
    }

    @Test("GitHub PAT (new) — github_pat_ prefix")
    func githubPatNew() {
        let input = "GitHub: \(Fixture.githubPatNew)"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:github-token]"))
    }

    @Test("GitHub classic — ghp_ prefix")
    func githubClassic() {
        let input = "Old GitHub: \(Fixture.githubClassic)"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:github-token]"))
    }

    @Test("Slack — xox prefix")
    func slackToken() {
        let input = "Slack 봇 token: \(Fixture.slackToken)"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:slack-token]"))
    }

    @Test("Private key PEM header")
    func privateKey() {
        let input = """
        -----BEGIN RSA PRIVATE KEY-----
        ABCDEFG
        -----END RSA PRIVATE KEY-----
        """
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:private-key]"))
    }

    @Test("한국 주민번호 — 6-7 digit pattern")
    func koreanRRN() {
        let input = "주민번호: 901101-1234567 입력"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:rrn]"))
        #expect(!result.contains("901101-1234567"))
    }

    @Test("신용카드 — 4-4-4-4 digit")
    func creditCard() {
        let input = "카드 4111 1111 1111 1111 입력"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:card]"))
    }

    @Test("신용카드 — dash separator")
    func creditCardDashed() {
        let input = "카드 4111-1111-1111-1111 입력"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:card]"))
    }

    @Test("Multiple secrets in one string — all masked")
    func multipleSecrets() {
        let input = "OpenAI: \(Fixture.openaiKey), AWS: \(Fixture.awsKey)"
        let result = SecretMasker.mask(input)
        #expect(result.contains("[REDACTED:openai-key]"))
        #expect(result.contains("[REDACTED:aws-access-key]"))
        #expect(!result.contains(Fixture.openaiKey))
        #expect(!result.contains(Fixture.awsKey))
    }

    @Test("Safe text — 변화 없음")
    func safeText() {
        let input = "Slack 어디 있어요? Chrome 켜주세요"
        let result = SecretMasker.mask(input)
        #expect(result == input)
    }

    @Test("Email — 현재 mask 안 함 (use case 보존)")
    func emailNotMasked() {
        let input = "내 이메일 user@example.com 어디 입력?"
        let result = SecretMasker.mask(input)
        #expect(result.contains("user@example.com"))
    }
}

@Suite("v0.2 — SecretMasker.detect")
struct SecretMaskerDetectTests {

    @Test("detect 반환 — name + matched")
    func detectReturnsHits() {
        let input = "\(Fixture.openaiKey) 있어요"
        let hits = SecretMasker.detect(input)
        #expect(hits.count == 1)
        #expect(hits[0].name == "openai-key")
        #expect(hits[0].matched.hasPrefix("sk-"))
    }

    @Test("detect — secret 없으면 empty")
    func detectEmpty() {
        let hits = SecretMasker.detect("그냥 텍스트")
        #expect(hits.isEmpty)
    }

    @Test("detect — 여러 종류 secret")
    func detectMultiple() {
        let input = "OpenAI: \(Fixture.openaiKey) + AWS: \(Fixture.awsKey) + card 4111-1111-1111-1111"
        let hits = SecretMasker.detect(input)
        #expect(hits.count >= 3)
        let names = hits.map { $0.name }
        #expect(names.contains("openai-key"))
        #expect(names.contains("aws-access-key"))
        #expect(names.contains("credit-card"))
    }
}

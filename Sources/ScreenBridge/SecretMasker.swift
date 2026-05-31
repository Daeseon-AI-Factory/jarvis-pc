//
//  SecretMasker.swift
//  ScreenBridge — v0.2 (보안 layer 1번)
//
//  Vision LLM 호출 *전*에 instruction + audit log 박을 텍스트에서 secret pattern
//  regex로 redact. v0.2 보안 5-layer 첫 번째 (memory: product-vision-global-multi-platform).
//
//  적용 layer:
//  - AnalyzeRequest.instruction (LLM에 보냄, *외부 서버 도달*)
//  - SessionAuditEntry.steps[].nextAction / targetText / stepActionSummary (디스크 영구)
//  - Log statements (os.Logger persistent log — 자녀가 sessions folder 봐도 안전)
//
//  *image masking 안 함* — Vision LLM은 OCR 후 처리 (image 자체 redact 복잡, v0.3+ 고려).
//  단 instruction에서 "내 카드 4111... 어디 입력?" 같은 raw 박기 차단.
//
//  Anti-false-positive: 너무 broad pattern (예: 32-char hex) 피함. Specific prefix 우선
//  (sk- / AKIA / ghp_). 의심 시 *redacted 안 함* (false negative > false positive — 사용자
//  본인이 redacted 보면 *왜* 의문).
//

import Foundation

enum SecretMasker {

    struct Pattern: Sendable {
        let name: String                   // "openai-key" 등
        let regex: NSRegularExpression
        let replacement: String            // "[REDACTED:openai-key]"
    }

    /// 모든 pattern. order matters — *specific* (sk-ant-) 가 *generic* (sk-) 앞.
    static let patterns: [Pattern] = {
        let raw: [(String, String, String)] = [
            // Anthropic — sk-ant 가 sk- 앞. generic sk- 안 잡힘.
            ("anthropic-key", #"sk-ant-[a-zA-Z0-9_-]{20,}"#, "[REDACTED:anthropic-key]"),
            // OpenAI — sk-proj 신형 + sk- generic
            ("openai-project-key", #"sk-proj-[a-zA-Z0-9_-]{40,}"#, "[REDACTED:openai-key]"),
            ("openai-key", #"sk-[a-zA-Z0-9]{20,}"#, "[REDACTED:openai-key]"),
            // Google AI Studio (Gemini)
            ("google-ai-key", #"AIza[a-zA-Z0-9_-]{35}"#, "[REDACTED:google-key]"),
            // AWS
            ("aws-access-key", #"AKIA[0-9A-Z]{16}"#, "[REDACTED:aws-access-key]"),
            // GitHub
            ("github-pat-new", #"github_pat_[a-zA-Z0-9_]{82}"#, "[REDACTED:github-token]"),
            ("github-token-classic", #"ghp_[a-zA-Z0-9]{36}"#, "[REDACTED:github-token]"),
            // Slack
            ("slack-token", #"xox[abprs]-[a-zA-Z0-9-]{10,}"#, "[REDACTED:slack-token]"),
            // Private key PEM
            ("private-key-pem", #"-----BEGIN [A-Z ]+PRIVATE KEY-----"#, "[REDACTED:private-key]"),
            // 한국 주민번호 (6-7 digit) — 너무 broad한 전화번호 X
            ("korean-rrn", #"\b\d{6}[-\s]\d{7}\b"#, "[REDACTED:rrn]"),
            // 신용카드 (4-4-4-4 digit) — VISA/Master/Amex 일반 형식
            ("credit-card", #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#, "[REDACTED:card]"),
            // email — non-specific하지만 *PII* 카테고리. 단 "support@example.com" 같은 public email도 잡힘.
            // → audit log에는 mask하지만 instruction에는 X (사용자가 "내 이메일 어디?" 시 인식 필요).
            // 현재는 *generic mask 안 함*. 단 specific call에 박을 수 있음 (maskForAudit).
        ]
        return raw.compactMap { (name, pattern, replacement) -> Pattern? in
            guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
            return Pattern(name: name, regex: r, replacement: replacement)
        }
    }()

    /// 모든 pattern 적용 (instruction + audit log + log statement용).
    /// Email은 mask 안 함 — instruction의 "내 이메일 [user@x.com] 입력" 같은 use case 보존.
    static func mask(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.regex.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: pattern.replacement
            )
        }
        return result
    }

    /// Detect-only (mask 안 함). 사용자 "이런 secret 있어요" alert용 (v0.3+ TODO).
    static func detect(_ text: String) -> [(name: String, matched: String)] {
        var hits: [(String, String)] = []
        for pattern in patterns {
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            let matches = pattern.regex.matches(in: text, options: [], range: range)
            for m in matches {
                let matchedStr = nsText.substring(with: m.range)
                hits.append((pattern.name, matchedStr))
            }
        }
        return hits
    }
}

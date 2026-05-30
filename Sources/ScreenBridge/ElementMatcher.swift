//
//  ElementMatcher.swift
//  ScreenBridge — Phase 6.1
//
//  `target_text` ↔ OCR boxes deterministic 매칭. fuzzy:
//    1. case-insensitive substring 매칭 우선 (간단, 정확)
//    2. fail 시 Levenshtein normalized similarity ≥ threshold (0.7) 검색
//    3. 둘 다 fail → nil → caller가 LLM coordinates fallback 또는 bubble만
//
//  결과 = screen-local logical pt CGRect (DisplayGeometry로 변환된 후) — HUDAnnotation.rect.
//

import CoreGraphics
import Foundation

enum ElementMatcher {

    /// 기본 threshold — Phase 6.1 commit 시 fixed. dogfooding 후 DECISIONS R9 entry로 튜닝.
    static let defaultThreshold: Double = 0.7

    /// 짧은 텍스트(≤6자) length-aware threshold — "Save" vs "Same" (0.75) false positive 차단.
    /// Phase 6.1 verify fix.
    static let shortTextThreshold: Double = 0.85

    /// `targetText`를 `candidates` 중 가장 매칭 잘 되는 OCRBox에 매핑.
    /// 매칭 성공 시 screen-local logical pt CGRect 반환 (HUDAnnotation.rect용).
    static func match(
        targetText: String,
        candidates: [OCRBox],
        geometry: DisplayGeometry,
        threshold: Double = defaultThreshold
    ) -> CGRect? {
        let normalizedTarget = normalize(targetText)
        guard !normalizedTarget.isEmpty, !candidates.isEmpty else { return nil }

        // 1. substring 매칭 (case-insensitive + NFC normalize + whitespace + punctuation strip)
        // 가장 짧은 (= 가장 specific) 매칭 우선. 같은 길이면 confidence 높은 박스 선택 (tiebreaker).
        let substringMatches = candidates.filter { box in
            normalize(box.text).contains(normalizedTarget)
        }
        if let best = substringMatches.sorted(by: { lhs, rhs in
            let lhsLen = normalize(lhs.text).count
            let rhsLen = normalize(rhs.text).count
            if lhsLen != rhsLen { return lhsLen < rhsLen }
            return lhs.confidence > rhs.confidence    // tiebreaker
        }).first {
            Log.dispatcher.info(
                "[match] substring hit — target=\"\(targetText, privacy: .public)\" box=\"\(best.text, privacy: .public)\""
            )
            return geometry.logicalRectFromSentBox(toIntBox(best.rectInSentImage))
        }

        // 2. fuzzy — Levenshtein normalized similarity.
        // 짧은 텍스트(≤6자) auto-tighten — 단 caller가 명시적으로 threshold 줬으면 그대로.
        let effectiveThreshold: Double = (threshold == Self.defaultThreshold && normalizedTarget.count <= 6)
            ? shortTextThreshold
            : threshold
        let scored: [(OCRBox, Double)] = candidates.compactMap { box in
            let sim = similarity(normalize(box.text), normalizedTarget)
            return sim >= effectiveThreshold ? (box, sim) : nil
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else {
            Log.dispatcher.notice(
                "[match] fail — target=\"\(targetText, privacy: .public)\" no candidate ≥ threshold \(effectiveThreshold, privacy: .public)"
            )
            return nil
        }
        Log.dispatcher.info(
            "[match] fuzzy hit — target=\"\(targetText, privacy: .public)\" box=\"\(best.0.text, privacy: .public)\" sim=\(String(format: "%.2f", best.1), privacy: .public)"
        )
        return geometry.logicalRectFromSentBox(toIntBox(best.0.rectInSentImage))
    }

    // MARK: - helpers

    /// `target_text` ↔ OCR text 정규화. 4단계:
    /// 1. **NFC Unicode normalization** — 한글 NFD(ㅎ+ㅏ+ㄴ) vs NFC(한) silent mismatch 차단 (verify HIGH).
    /// 2. `lowercased()` — case-insensitive.
    /// 3. Punctuation strip — `.txt` vs `txt`, `File:` vs `File` 같은 OCR error 흡수.
    /// 4. Whitespace 정규화 — multi-space → single space.
    static func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping    // NFC: 한글 자모 합성
            .lowercased()
            .unicodeScalars
            .filter { !CharacterSet.punctuationCharacters.contains($0) }
            .map { String($0) }
            .joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func toIntBox(_ rect: CGRect) -> [Int] {
        [
            Int(rect.origin.x.rounded()),
            Int(rect.origin.y.rounded()),
            Int(rect.width.rounded()),
            Int(rect.height.rounded()),
        ]
    }

    /// Normalized Levenshtein similarity. 1.0 = identical, 0.0 = max different.
    static func similarity(_ a: String, _ b: String) -> Double {
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        let dist = levenshtein(a, b)
        return 1.0 - Double(dist) / Double(maxLen)
    }

    /// Classic Levenshtein. Iterative two-row DP.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,           // deletion
                    curr[j - 1] + 1,       // insertion
                    prev[j - 1] + cost     // substitution
                )
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}

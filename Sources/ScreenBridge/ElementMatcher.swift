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

/// 통합 candidate type — OCR box와 AX element를 같은 매칭 파이프라인으로 처리.
/// `rectInLogicalPt`는 screen-global logical pt — HUDAnnotation에 *바로* 사용 가능.
struct MatchCandidate: Sendable {
    let text: String
    let rectInLogicalPt: CGRect
    let confidence: Float
    let source: Source

    enum Source: Sendable, Equatable {
        case ocr
        case ax(role: String)
    }
}

enum ElementMatcher {

    /// 기본 threshold — Phase 6.1 commit 시 fixed. dogfooding 후 DECISIONS R9 entry로 튜닝.
    static let defaultThreshold: Double = 0.7

    /// 짧은 텍스트(≤6자) length-aware threshold — "Save" vs "Same" (0.75) false positive 차단.
    /// Phase 6.1 verify fix.
    static let shortTextThreshold: Double = 0.85

    /// LLM이 *대략적 영역 hint*를 줬을 때 — 그 중심 기준 ±radius 안 OCR 박스만 candidate.
    /// wrong-box 차단 핵심 (Phase 6.1 spatial fusion).
    /// 200pt = 1568px sent image에서 약 ~12.7% 너비 — Dock 영역 / dialog / toolbar 정도.
    static let defaultProximityRadius: CGFloat = 200

    /// `targetText`를 `candidates` 중 가장 매칭 잘 되는 OCRBox에 매핑.
    /// 매칭 성공 시 screen-local logical pt CGRect 반환 (HUDAnnotation.rect용).
    ///
    /// `llmHintRect`: LLM이 추정한 *sent image px* 좌표 (top-left). 있으면 그 중심 기준
    /// ±`proximityRadius` 안 candidates만 매칭 시도. 화면 여러 영역에 같은 텍스트
    /// 있을 때 (예: VS Code conversation의 "slack" vs Dock의 Slack 아이콘 라벨) wrong-box 차단.
    /// hint 근처 OCR 박스 없으면 *full candidates fallback* (LLM hint 부정확 시 안전망).
    static func match(
        targetText: String,
        candidates: [OCRBox],
        geometry: DisplayGeometry,
        llmHintRect: CGRect? = nil,
        proximityRadius: CGFloat = defaultProximityRadius,
        threshold: Double = defaultThreshold
    ) -> CGRect? {
        let normalizedTarget = normalize(targetText)
        guard !normalizedTarget.isEmpty, !candidates.isEmpty else { return nil }

        // Spatial fusion: LLM hint 있으면 proximity filter — hint 중심 ±radius 안 박스만.
        let effectiveCandidates: [OCRBox]
        if let hint = llmHintRect {
            let hintCenter = CGPoint(x: hint.midX, y: hint.midY)
            let nearby = candidates.filter { box in
                let bc = CGPoint(x: box.rectInSentImage.midX, y: box.rectInSentImage.midY)
                let dx = bc.x - hintCenter.x
                let dy = bc.y - hintCenter.y
                return sqrt(dx * dx + dy * dy) <= proximityRadius
            }
            if nearby.isEmpty {
                // LLM hint 근처 박스 없음 — hint가 부정확했을 가능성. full candidates fallback.
                Log.dispatcher.notice(
                    "[match] proximity filter: 0/\(candidates.count, privacy: .public) near LLM hint — full fallback"
                )
                effectiveCandidates = candidates
            } else {
                Log.dispatcher.info(
                    "[match] proximity filter: \(nearby.count, privacy: .public)/\(candidates.count, privacy: .public) near LLM hint (radius=\(Int(proximityRadius), privacy: .public)px)"
                )
                effectiveCandidates = nearby
            }
        } else {
            effectiveCandidates = candidates
        }

        // 1. substring 매칭 (case-insensitive + NFC normalize + whitespace + punctuation strip)
        // 가장 짧은 (= 가장 specific) 매칭 우선. 같은 길이면 confidence 높은 박스 선택 (tiebreaker).
        let substringMatches = effectiveCandidates.filter { box in
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
        let scored: [(OCRBox, Double)] = effectiveCandidates.compactMap { box in
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

    // MARK: - Unified MatchCandidate match (Phase 6.2 OCR + AX hybrid)

    /// OCR boxes + AX elements 합집합에서 매칭. proximity / substring / fuzzy 동일 알고리즘.
    /// 결과 = screen-global logical pt CGRect (HUDAnnotation에 그대로 사용 가능).
    ///
    /// `proximityRadius`는 logical pt 단위 (~100pt = sent 200px와 유사 — Retina 2x 가정).
    static func match(
        targetText: String,
        candidates: [MatchCandidate],
        llmHintRect: CGRect? = nil,
        proximityRadius: CGFloat = 100,
        threshold: Double = defaultThreshold
    ) -> CGRect? {
        let normalizedTarget = normalize(targetText)
        guard !normalizedTarget.isEmpty, !candidates.isEmpty else { return nil }

        // Spatial fusion — LLM hint 있으면 proximity filter.
        let effective: [MatchCandidate]
        if let hint = llmHintRect {
            let hc = CGPoint(x: hint.midX, y: hint.midY)
            let nearby = candidates.filter { c in
                let bc = CGPoint(x: c.rectInLogicalPt.midX, y: c.rectInLogicalPt.midY)
                return hypot(bc.x - hc.x, bc.y - hc.y) <= proximityRadius
            }
            if nearby.isEmpty {
                Log.dispatcher.notice(
                    "[match] proximity filter: 0/\(candidates.count, privacy: .public) near LLM hint — full fallback"
                )
                effective = candidates
            } else {
                Log.dispatcher.info(
                    "[match] proximity filter: \(nearby.count, privacy: .public)/\(candidates.count, privacy: .public) near LLM hint (radius=\(Int(proximityRadius), privacy: .public)pt)"
                )
                effective = nearby
            }
        } else {
            effective = candidates
        }

        // 1. substring 매칭 — confidence + AX 우선 (icon-only는 OCR이 못 잡으니 AX가 정답).
        let substringMatches = effective.filter { normalize($0.text).contains(normalizedTarget) }
        if let best = substringMatches.sorted(by: { lhs, rhs in
            let lhsLen = normalize(lhs.text).count
            let rhsLen = normalize(rhs.text).count
            if lhsLen != rhsLen { return lhsLen < rhsLen }
            // 동일 길이 — AX 우선 (deterministic 좌표), confidence tiebreaker
            let lhsAX = isAX(lhs.source)
            let rhsAX = isAX(rhs.source)
            if lhsAX != rhsAX { return lhsAX }
            return lhs.confidence > rhs.confidence
        }).first {
            Log.dispatcher.info(
                "[match] substring hit — target=\"\(targetText, privacy: .public)\" element=\"\(best.text, privacy: .public)\" source=\(sourceTag(best.source), privacy: .public)"
            )
            return best.rectInLogicalPt
        }

        // 2. fuzzy — Levenshtein normalized similarity, length-aware threshold.
        let effectiveThreshold: Double = (threshold == Self.defaultThreshold && normalizedTarget.count <= 6)
            ? shortTextThreshold
            : threshold
        let scored: [(MatchCandidate, Double)] = effective.compactMap { c in
            let sim = similarity(normalize(c.text), normalizedTarget)
            return sim >= effectiveThreshold ? (c, sim) : nil
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else {
            Log.dispatcher.notice(
                "[match] fail — target=\"\(targetText, privacy: .public)\" no candidate ≥ threshold \(effectiveThreshold, privacy: .public)"
            )
            return nil
        }
        Log.dispatcher.info(
            "[match] fuzzy hit — target=\"\(targetText, privacy: .public)\" element=\"\(best.0.text, privacy: .public)\" source=\(sourceTag(best.0.source), privacy: .public) sim=\(String(format: "%.2f", best.1), privacy: .public)"
        )
        return best.0.rectInLogicalPt
    }

    private static func isAX(_ source: MatchCandidate.Source) -> Bool {
        if case .ax = source { return true } else { return false }
    }

    private static func sourceTag(_ source: MatchCandidate.Source) -> String {
        switch source {
        case .ocr: return "ocr"
        case .ax(let role): return "ax:\(role)"
        }
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

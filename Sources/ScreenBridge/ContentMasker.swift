//
//  ContentMasker.swift
//  ScreenBridge — v0.3 Layer 2.5 (5-layer 보안)
//
//  Layer 1 (SecretMasker)은 *instruction text*만 mask — image / OCR / AX 결과는 그대로.
//  Layer 2 (SensitivityRouter)는 *frontmost app*만 검사 — 일반 앱 안 민감 row 미박힘.
//  Layer 4 (Qwen local)는 진짜 답 — 단 1-3개월 박는 중.
//
//  ContentMasker (Layer 2.5)는 *OCR/AX candidates 안에서* 민감 정보 detect 시:
//  - target_text가 *민감 row 안 박힌* candidate인 경우 → candidate에서 제외
//    (LLM이 "여기 카드번호 4111-... 누르세요" 안내 X)
//  - 또는 *image-level redact* — 단 image 처리 복잡, v0.3는 *candidate filter*만.
//
//  SecretMasker.patterns 재사용 — 동일 regex (sk-/AKIA/카드/주민/계좌/...).
//

import Foundation

enum ContentMasker {

    struct FilterResult: Sendable {
        let filteredCandidates: [MatchCandidate]
        let redactedCount: Int
        let categoriesHit: [String]   // 박힌 pattern name (e.g. "credit-card", "korean-rrn")
    }

    /// OCR/AX candidates 중 *민감 pattern* 박힌 거 제외.
    /// LLM이 *카드번호 row*나 *비밀번호 입력*를 target으로 잡지 못함.
    static func filterSensitiveCandidates(_ candidates: [MatchCandidate]) -> FilterResult {
        var filtered: [MatchCandidate] = []
        var redactedCount = 0
        var categories: Set<String> = []

        for candidate in candidates {
            let hits = SecretMasker.detect(candidate.text)
            if hits.isEmpty {
                filtered.append(candidate)
            } else {
                redactedCount += 1
                for hit in hits {
                    categories.insert(hit.name)
                }
            }
        }

        return FilterResult(
            filteredCandidates: filtered,
            redactedCount: redactedCount,
            categoriesHit: Array(categories).sorted()
        )
    }
}

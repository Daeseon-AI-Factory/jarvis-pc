//
//  ContentMaskerTests.swift
//  ScreenBridgeTests — v0.3 Layer 2.5
//

import CoreGraphics
import Foundation
import Testing
@testable import ScreenBridge

@Suite("v0.3 Layer 2.5 — ContentMasker.filterSensitiveCandidates")
struct ContentMaskerTests {

    private func candidate(_ text: String) -> MatchCandidate {
        MatchCandidate(
            text: text,
            rectInLogicalPt: CGRect(x: 0, y: 0, width: 100, height: 30),
            confidence: 0.9,
            source: .ocr
        )
    }

    @Test("일반 candidate (Chrome / Settings 등) → 그대로 통과")
    func normalCandidatesPass() {
        let candidates = [candidate("Chrome"), candidate("Settings"), candidate("Save")]
        let result = ContentMasker.filterSensitiveCandidates(candidates)
        #expect(result.filteredCandidates.count == 3)
        #expect(result.redactedCount == 0)
        #expect(result.categoriesHit.isEmpty)
    }

    @Test("카드번호 박힌 row → 제외")
    func creditCardRedacted() {
        let candidates = [
            candidate("Total"),
            candidate("4111 1111 1111 1111"),
            candidate("Save"),
        ]
        let result = ContentMasker.filterSensitiveCandidates(candidates)
        #expect(result.filteredCandidates.count == 2)
        #expect(result.redactedCount == 1)
        #expect(result.categoriesHit.contains("credit-card"))
    }

    @Test("주민번호 박힌 row → 제외")
    func koreanRRNRedacted() {
        let candidates = [candidate("이름"), candidate("901101-1234567")]
        let result = ContentMasker.filterSensitiveCandidates(candidates)
        #expect(result.filteredCandidates.count == 1)
        #expect(result.redactedCount == 1)
        #expect(result.categoriesHit.contains("korean-rrn"))
    }

    @Test("한국 휴대폰 박힌 row → 제외")
    func koreanMobileRedacted() {
        let candidates = [candidate("연락처"), candidate("010-1234-5678"), candidate("전송")]
        let result = ContentMasker.filterSensitiveCandidates(candidates)
        #expect(result.filteredCandidates.count == 2)
        #expect(result.redactedCount == 1)
        #expect(result.categoriesHit.contains("korean-mobile"))
    }

    @Test("multiple 민감 row → 모두 제외 + categoriesHit 모음")
    func multipleSensitive() {
        let candidates = [
            candidate("Profile"),
            candidate("010-9876-5432"),
            candidate("4111-2222-3333-4444"),
            candidate("901101-1234567"),
            candidate("Confirm"),
        ]
        let result = ContentMasker.filterSensitiveCandidates(candidates)
        #expect(result.filteredCandidates.count == 2)
        #expect(result.redactedCount == 3)
        #expect(result.categoriesHit.contains("credit-card"))
        #expect(result.categoriesHit.contains("korean-rrn"))
        #expect(result.categoriesHit.contains("korean-mobile"))
    }

    @Test("빈 candidates → 빈 result")
    func emptyCandidates() {
        let result = ContentMasker.filterSensitiveCandidates([])
        #expect(result.filteredCandidates.isEmpty)
        #expect(result.redactedCount == 0)
        #expect(result.categoriesHit.isEmpty)
    }
}

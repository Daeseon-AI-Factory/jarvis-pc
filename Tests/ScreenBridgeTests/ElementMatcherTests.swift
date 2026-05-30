//
//  ElementMatcherTests.swift
//  ScreenBridgeTests — Phase 6.1
//

import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import ScreenBridge

@Suite("ElementMatcher")
struct ElementMatcherTests {

    private func mockGeometry() -> DisplayGeometry {
        DisplayGeometry(
            displayID: 1,
            screenFrame: NSRect(x: 0, y: 0, width: 1024, height: 768),
            backingScaleFactor: 1.0,
            physicalSize: CGSize(width: 1024, height: 768),
            sentSize: CGSize(width: 1024, height: 768)
        )
    }

    private func box(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ conf: Float = 0.95) -> OCRBox {
        OCRBox(
            text: text,
            rectInSentImage: CGRect(x: x, y: y, width: w, height: h),
            confidence: conf
        )
    }

    // MARK: - substring 매칭

    @Test("정확 substring 매칭 — 'CLAUDE.md' in box list")
    func substringMatch() {
        let candidates = [
            box("README.md", 100, 200, 150, 30),
            box("CLAUDE.md", 100, 240, 150, 30),
            box("PRODUCT.md", 100, 280, 150, 30),
        ]
        let rect = ElementMatcher.match(targetText: "CLAUDE.md", candidates: candidates, geometry: mockGeometry())
        #expect(rect != nil)
        #expect(rect?.minX == 100)
        #expect(rect?.minY == 240)
        #expect(rect?.width == 150)
    }

    @Test("case-insensitive — 'claude.md' targets 'CLAUDE.md'")
    func caseInsensitive() {
        let candidates = [
            box("README.md", 100, 200, 150, 30),
            box("CLAUDE.md", 100, 240, 150, 30),
        ]
        let rect = ElementMatcher.match(targetText: "claude.md", candidates: candidates, geometry: mockGeometry())
        #expect(rect?.minY == 240)
    }

    @Test("partial substring — 'Settings' targets 'Open Settings'")
    func partialSubstring() {
        let candidates = [
            box("Open Settings", 100, 200, 200, 30),
            box("Save", 100, 240, 100, 30),
        ]
        let rect = ElementMatcher.match(targetText: "Settings", candidates: candidates, geometry: mockGeometry())
        #expect(rect?.minX == 100)
        #expect(rect?.minY == 200)
    }

    @Test("specific 우선 — 'Sign in' 매칭 시 'Sign in' 자체가 'Sign in with Google'보다 우선")
    func specificMatchWins() {
        let candidates = [
            box("Sign in with Google", 100, 200, 250, 30),
            box("Sign in", 400, 240, 120, 30),
        ]
        let rect = ElementMatcher.match(targetText: "Sign in", candidates: candidates, geometry: mockGeometry())
        // 'Sign in' (7글자) < 'Sign in with Google' (19글자) → 'Sign in' 박스 선택
        #expect(rect?.minX == 400)
        #expect(rect?.minY == 240)
    }

    // MARK: - fuzzy 매칭

    @Test("fuzzy — 'settings' targets 'setting' (OCR typo 1자 drop, Levenshtein 1/8 = 0.875)")
    func fuzzyMatch() {
        // target 'settings' (8자, default threshold 0.7) — 'setting' (1글자 drop OCR error)
        // normalize: 'settings'(8) vs 'setting'(7). substring 'settings' in 'setting'? No (target longer).
        // Levenshtein 1, max 8. sim = 0.875 ≥ 0.7 → match.
        let candidates = [
            box("setting", 100, 240, 150, 30),    // OCR typo
            box("README", 200, 280, 150, 30),     // 완전 다름
        ]
        let rect = ElementMatcher.match(targetText: "settings", candidates: candidates, geometry: mockGeometry())
        #expect(rect?.minY == 240)
    }

    @Test("punctuation strip 후 'md' vs 'txt' 다른 파일은 reject (정확한 본질)")
    func punctuationDifferentExtRejected() {
        // target 'CLAUDE.md'(9자→strip 8자), box 'CLAUDE.txt'(10자→strip 9자)
        // strip 후 'claudemd' vs 'claudetxt'. Levenshtein 3, max 9. sim 0.67 < 0.7 → reject.
        // *번역기 본질*: md와 txt는 다른 파일 — 매칭 reject가 정확.
        let candidates = [box("CLAUDE.txt", 100, 240, 150, 30)]
        let rect = ElementMatcher.match(targetText: "CLAUDE.md", candidates: candidates, geometry: mockGeometry())
        #expect(rect == nil)
    }

    @Test("threshold 미만 → nil")
    func belowThreshold() {
        let candidates = [
            box("totally different text", 100, 240, 200, 30),
        ]
        let rect = ElementMatcher.match(targetText: "CLAUDE.md", candidates: candidates, geometry: mockGeometry())
        #expect(rect == nil)
    }

    @Test("threshold 커스터마이즈 — caller가 명시 시 short text auto-tighten 무시 (verify fix)")
    func customThreshold() {
        // target 'CMD' (3자) — short text → default threshold (0.7) 사용 시 auto 0.85.
        // box 'CMG' — 1글자 다름, max 3. Levenshtein 1, sim = 1 - 1/3 = 0.667.
        let candidates = [box("CMG", 100, 240, 100, 30)]
        // default → auto-tighten 0.85 → 0.667 < 0.85 → reject
        let rectDefault = ElementMatcher.match(targetText: "CMD", candidates: candidates, geometry: mockGeometry())
        #expect(rectDefault == nil)
        // 명시 threshold 0.5 → auto-tighten 무시 → 0.667 ≥ 0.5 → match
        let rectRelaxed = ElementMatcher.match(targetText: "CMD", candidates: candidates, geometry: mockGeometry(), threshold: 0.5)
        #expect(rectRelaxed != nil)
    }

    // MARK: - edge cases

    @Test("빈 targetText → nil")
    func emptyTargetText() {
        let candidates = [box("anything", 100, 200, 100, 30)]
        let rect = ElementMatcher.match(targetText: "", candidates: candidates, geometry: mockGeometry())
        #expect(rect == nil)
    }

    @Test("빈 candidates → nil")
    func emptyCandidates() {
        let rect = ElementMatcher.match(targetText: "Sign in", candidates: [], geometry: mockGeometry())
        #expect(rect == nil)
    }

    @Test("whitespace normalize — '  Sign  in  ' = 'Sign in'")
    func normalizeWhitespace() {
        let candidates = [box("Sign in", 100, 200, 100, 30)]
        let rect = ElementMatcher.match(targetText: "  Sign  in  ", candidates: candidates, geometry: mockGeometry())
        #expect(rect != nil)
    }

    // MARK: - helpers (직접 lock)

    @Test("levenshtein — 동일=0, 한 글자 변경=1, 빈 vs N=N")
    func levenshteinBasics() {
        #expect(ElementMatcher.levenshtein("abc", "abc") == 0)
        #expect(ElementMatcher.levenshtein("abc", "abd") == 1)
        #expect(ElementMatcher.levenshtein("", "abcd") == 4)
        #expect(ElementMatcher.levenshtein("kitten", "sitting") == 3)
    }

    @Test("similarity — 동일=1.0, 완전 다름=0.0")
    func similarityBounds() {
        #expect(ElementMatcher.similarity("abc", "abc") == 1.0)
        #expect(ElementMatcher.similarity("", "") == 1.0)
        let diff = ElementMatcher.similarity("abc", "xyz")
        #expect(diff >= 0.0 && diff <= 1.0)
        // abc vs xyz 모두 3글자, 3개 다름 → 1 - 3/3 = 0
        #expect(diff == 0.0)
    }

    // MARK: - verify fix tests

    @Test("Unicode NFC normalization — 한글 NFD vs NFC 매칭 (verify HIGH fix)")
    func unicodeNFCNormalization() {
        // Swift String의 == 는 canonical equivalence라 NFC/NFD 같다고 인식 — sanity assert X.
        // 단 underlying unicodeScalars는 다름. 명시적 normalize가 defensive measure.
        let nfcText = "한글 메뉴"
        let nfdText = nfcText.decomposedStringWithCanonicalMapping
        // unicodeScalars 비교 — 실제로 다른 코드포인트
        #expect(Array(nfcText.unicodeScalars) != Array(nfdText.unicodeScalars))

        // OCR 결과가 NFD로 들어와도 (드물지만 가능), normalize의 NFC 통일로 매칭
        let candidates = [box(nfdText, 100, 200, 150, 30)]
        let rect = ElementMatcher.match(targetText: nfcText, candidates: candidates, geometry: mockGeometry())
        #expect(rect != nil)
    }

    @Test("짧은 텍스트(≤6자) fuzzy threshold 0.85 — 'Save' vs 'Same' false positive 차단 (verify HIGH fix)")
    func shortTextStricterThreshold() {
        // 'Save'(4자) vs 'Same' (1글자 다름) — Levenshtein 1/4 = 0.75
        // 기존 0.7 threshold → false positive. 새 0.85 → reject.
        let candidates = [box("Same", 100, 200, 80, 25)]
        let rect = ElementMatcher.match(targetText: "Save", candidates: candidates, geometry: mockGeometry())
        #expect(rect == nil)  // 0.75 < 0.85 → reject (wrong-box 방지)
    }

    @Test("짧은 텍스트 — substring 매칭은 여전히 통과 (length threshold는 fuzzy에만)")
    func shortTextSubstringStillWorks() {
        let candidates = [box("Save", 100, 200, 80, 25)]
        let rect = ElementMatcher.match(targetText: "Save", candidates: candidates, geometry: mockGeometry())
        #expect(rect != nil)  // substring 정확 매칭 — threshold 무관
    }

    @Test("Punctuation 무시 — 'CLAUDE.md' vs 'CLAUDE md' (OCR이 점 drop) 매칭 (verify HIGH fix)")
    func punctuationStripped() {
        let candidates = [box("CLAUDE md", 100, 200, 150, 30)]
        let rect = ElementMatcher.match(targetText: "CLAUDE.md", candidates: candidates, geometry: mockGeometry())
        // normalize 후 'claudemd' == 'claudemd' substring 매칭
        #expect(rect != nil)
    }

    @Test("Tiebreaker — 동일 길이 substring 매칭 시 confidence 높은 박스 우선 (verify MEDIUM fix)")
    func confidenceTiebreaker() {
        let candidates = [
            box("Save", 100, 200, 80, 25, 0.80),    // 첫 번째, lower confidence
            box("Save", 500, 200, 80, 25, 0.95),    // 두 번째, higher confidence
        ]
        let rect = ElementMatcher.match(targetText: "Save", candidates: candidates, geometry: mockGeometry())
        // 같은 길이 'save' 둘 — confidence 0.95 박스 선택 (x=500).
        #expect(rect?.minX == 500)
    }
}

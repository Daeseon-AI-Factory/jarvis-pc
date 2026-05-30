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

    @Test("fuzzy — 'CLAUDE.md' targets 'CLAUDE.txt' (Levenshtein 2/9 = 0.78 sim)")
    func fuzzyMatch() {
        let candidates = [
            box("CLAUDE.txt", 100, 240, 150, 30),    // sim 0.78 ≥ 0.7
            box("README.md", 200, 280, 150, 30),     // sim ~0.5
        ]
        let rect = ElementMatcher.match(targetText: "CLAUDE.md", candidates: candidates, geometry: mockGeometry())
        // substring match 실패 (txt ≠ md) → fuzzy → CLAUDE.txt 매칭
        #expect(rect?.minY == 240)
    }

    @Test("threshold 미만 → nil")
    func belowThreshold() {
        let candidates = [
            box("totally different text", 100, 240, 200, 30),
        ]
        let rect = ElementMatcher.match(targetText: "CLAUDE.md", candidates: candidates, geometry: mockGeometry())
        #expect(rect == nil)
    }

    @Test("threshold 커스터마이즈 — 0.5로 낮추면 더 관대")
    func customThreshold() {
        let candidates = [
            box("CLAUDE", 100, 240, 100, 30),    // sim 6/9 ≈ 0.67 — default 0.7 미만
        ]
        // default threshold (0.7) → fail
        let rectDefault = ElementMatcher.match(targetText: "CLAUDE.md", candidates: candidates, geometry: mockGeometry())
        #expect(rectDefault == nil)
        // threshold 0.5 → match
        let rectRelaxed = ElementMatcher.match(targetText: "CLAUDE.md", candidates: candidates, geometry: mockGeometry(), threshold: 0.5)
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
}

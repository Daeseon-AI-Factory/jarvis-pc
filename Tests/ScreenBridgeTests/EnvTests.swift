//
//  EnvTests.swift
//  ScreenBridgeTests — Phase 2.2
//

import Testing
@testable import ScreenBridge

@Suite("Env")
struct EnvTests {

    @Test("parse — 기본 KEY=VALUE")
    func parsesBasic() {
        let r = Env.parse("FOO=bar\nBAZ=qux")
        #expect(r["FOO"] == "bar")
        #expect(r["BAZ"] == "qux")
    }

    @Test("parse — # 주석 + 빈 줄 무시")
    func parsesCommentsAndBlanks() {
        let r = Env.parse("""
        # comment line
        \n
        FOO=bar
        # another comment
        \n
        BAZ=qux
        """)
        #expect(r.count == 2)
        #expect(r["FOO"] == "bar")
        #expect(r["BAZ"] == "qux")
    }

    @Test("parse — double quote, single quote 둘 다 strip")
    func parsesQuotes() {
        let r = Env.parse("""
        DQ="hello world"
        SQ='hello world'
        NQ=no quotes
        """)
        #expect(r["DQ"] == "hello world")
        #expect(r["SQ"] == "hello world")
        #expect(r["NQ"] == "no quotes")
    }

    @Test("parse — `export KEY=...` 접두 허용 (shell rc 호환)")
    func parsesExportPrefix() {
        let r = Env.parse("export FOO=bar")
        #expect(r["FOO"] == "bar")
    }

    @Test("parse — leading/trailing whitespace strip")
    func parsesWhitespace() {
        let r = Env.parse("  FOO  =  bar  ")
        #expect(r["FOO"] == "bar")
    }

    @Test("parse — `=` 없는 줄 무시")
    func parsesIgnoresInvalidLines() {
        let r = Env.parse("invalid line\nFOO=bar")
        #expect(r.count == 1)
        #expect(r["FOO"] == "bar")
    }

    @Test("string — process env에 set된 키 반환 (PATH는 항상 존재)")
    func stringReturnsProcessEnv() {
        #expect(Env.string("PATH") != nil)
    }

    @Test("string — 존재하지 않는 키는 nil")
    func stringReturnsNil() {
        #expect(Env.string("SCREENBRIDGE_NONEXISTENT_KEY_XYZ_12345") == nil)
    }
}

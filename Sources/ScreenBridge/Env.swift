//
//  Env.swift
//  ScreenBridge — Phase 2.2
//
//  Process env + .env 파일 폴백. dep 0 (CLAUDE.md 절대규칙 정신).
//

import Foundation

enum Env {
    /// Process env에서 키 조회. 없거나 빈 문자열이면 `.env` 파일 폴백. 둘 다 없으면 nil.
    static func string(_ key: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty {
            return v
        }
        return dotEnvCache[key]
    }

    private static let dotEnvCache: [String: String] = {
        let candidates: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".env"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".screenbridge/.env"),
        ]
        for url in candidates {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return parse(content)
            }
        }
        return [:]
    }()

    /// `.env` 파싱: `KEY=VALUE` per line, `#` 주석, 빈 줄 무시.
    /// 값 양쪽 quote (`"..."`, `'...'`) 자동 제거. `export KEY=...` 접두 허용.
    static func parse(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count))
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2 {
                let first = value.first!
                let last = value.last!
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
            }
            result[String(key)] = String(value)
        }
        return result
    }
}

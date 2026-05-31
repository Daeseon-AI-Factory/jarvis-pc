//
//  SessionAuditLog.swift
//  ScreenBridge — Phase 7.3
//
//  연속 작업 session의 audit log. ~/Library/Application Support/com.screenbridge.app/sessions/<uuid>.json
//  append-only, never cloud-synced (safety invariant 박힘 in Phase 7.0 synthesis).
//
//  목적:
//  - 디버그: 어떤 task가 어떻게 진행됐는지 retro 분석
//  - 신뢰: 사용자가 "ScreenBridge가 무엇을 봤나" 확인 가능 (menu-bar "Open sessions folder")
//  - 분석: 어머님 dogfooding 시 *어디서 막혔나* 패턴 추출
//
//  안전:
//  - screenshot 박지 X (text summary only — bounded growth 결정 일관)
//  - secret regex masking 통과 후 박힘 (v0.2 SecretMasker)
//  - 7일 후 자동 삭제 (TODO Phase 7.4)
//

import Foundation

/// 단일 session의 entire record. 매 step append (atomic write) + complete/cancel 시 finalize.
struct SessionAuditEntry: Codable, Sendable {
    let sessionID: String
    let instruction: String
    let startedAt: Date
    var steps: [StepRecord]
    var completedAt: Date?
    var outcome: Outcome

    enum Outcome: String, Codable, Sendable {
        case inProgress = "in_progress"
        case completed = "completed"
        case cancelledByUser = "cancelled_by_user"
        case cancelledByTimeout = "cancelled_by_timeout"
        case error = "error"
    }

    struct StepRecord: Codable, Sendable {
        let stepNumber: Int
        let targetText: String
        let nextAction: String
        let sourceTag: String              // "AX:AXDockItem" / "OCR" / "LLM" 등
        let stepActionSummary: String?
        let requiresConfirmation: Bool     // 위험 동작 (송금/삭제 등) trigger 여부
        let analysisElapsedSec: Double
        let timestamp: Date
    }
}

enum SessionAuditLog {

    /// `~/Library/Application Support/com.screenbridge.app/sessions/`
    /// 처음 호출 시 mkdir. 권한 issue 시 silent fail (audit log는 best-effort).
    static var directory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("com.screenbridge.app/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// session entry 저장 — 매 step / 완료 시점에 호출. atomic write.
    static func save(_ entry: SessionAuditEntry) {
        guard let dir = directory else { return }
        let path = dir.appendingPathComponent("\(entry.sessionID).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            try data.write(to: path, options: .atomic)
        } catch {
            // best-effort — audit log 실패가 session 자체 막지 않음.
            Log.app.notice("[audit] save failed sessionID=\(entry.sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// session entry 로드 — 디버그 / test 용.
    static func load(sessionID: String) -> SessionAuditEntry? {
        guard let dir = directory else { return nil }
        let path = dir.appendingPathComponent("\(sessionID).json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionAuditEntry.self, from: data)
    }
}

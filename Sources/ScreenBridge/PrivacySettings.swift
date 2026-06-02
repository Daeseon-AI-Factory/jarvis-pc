//
//  PrivacySettings.swift
//  ScreenBridge — v0.3 Privacy mode toggle
//
//  사용자가 menu-bar "환경설정..." → SettingsView에서 Privacy mode 선택.
//  UserDefaults 저장. 다음 launch 시 dispatcher 결정 박힌 거 박음.
//
//  v0.4 plan: runtime swap (재시작 X). 현재는 *재시작 후 적용*.
//

import Foundation
import SwiftUI

enum PrivacyMode: String, CaseIterable, Sendable, Identifiable {
    /// SCREENBRIDGE_USE_LOCAL env var 그대로 (default).
    /// 박힘 = local + cloud fallback. 안 박힘 = cloud only.
    case auto = "auto"

    /// 항상 cloud (Gemini/Claude). 빠름 + 비용 작음 + 단 외부 전송.
    case cloud = "cloud"

    /// 항상 local (Qwen). 외부 0 + 단 느림 (4-8s) + 모델 download 2GB.
    /// 단 SCREENBRIDGE_USE_LOCAL 박혀있어야 동작 (cloud key 박혀있으면 fallback).
    case alwaysLocal = "always-local"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "자동 (env)"
        case .cloud: return "Cloud (빠름)"
        case .alwaysLocal: return "Local only (안전)"
        }
    }

    var description: String {
        switch self {
        case .auto: return "환경변수 SCREENBRIDGE_USE_LOCAL로 결정. dev 환경 default."
        case .cloud: return "Gemini/Claude로 화면 전송. 빠르지만 외부 서버에 도달."
        case .alwaysLocal: return "Qwen2.5-VL-3B local 모델만 사용. 외부 0 — 단 모델 다운로드 ~2GB 필요."
        }
    }
}

@MainActor
final class PrivacySettings: ObservableObject {
    static let shared = PrivacySettings()

    private let modeKey = "screenbridge.privacy.mode"

    @Published var mode: PrivacyMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: modeKey) ?? PrivacyMode.auto.rawValue
        self.mode = PrivacyMode(rawValue: raw) ?? .auto
    }

    /// Dispatcher 결정 시 호출 — env var + setting 조합.
    /// auto + env=1 → local / auto + env X → cloud
    /// cloud → 항상 cloud / alwaysLocal → 항상 local
    nonisolated static func effectiveUseLocal() -> Bool {
        let envUseLocal = Env.string("SCREENBRIDGE_USE_LOCAL") == "1"
        let raw = UserDefaults.standard.string(forKey: "screenbridge.privacy.mode") ?? PrivacyMode.auto.rawValue
        let mode = PrivacyMode(rawValue: raw) ?? .auto
        switch mode {
        case .auto: return envUseLocal
        case .cloud: return false
        case .alwaysLocal: return true
        }
    }
}

//
//  SensitivityRouter.swift
//  ScreenBridge — v0.3 Layer 2 (5-layer 보안)
//
//  사용자 우려 (2026-05-30) "이거 진짜 보안문제되겠는데 제미나이가 다 볼거아니냐":
//  화면 전체 cloud로 보냄 → 옆 앱 데이터 다 보임.
//
//  Router는 *capture 시점* frontmost app의 bundleID 확인 후:
//  - deny-list 매칭 → .blockedLocalModelNotInstalled (v0.2/cloud 모드)
//                  → .localOnly (v0.3 Qwen 박힌 후)
//  - 그 외 → .cloud (기존 dispatcher 통과)
//
//  Fail-closed 정책: deny-list 매칭 + Qwen 미박힘 → *cloud로 안 보냄* + 사용자 alert.
//
//  Layer 1 (SecretMasker text) + Layer 2 (이 Router) + Layer 5 (audit log) = 5-layer 중 3/5 박힘.
//  Layer 3 (region opt-out) + Layer 4 (Qwen local) = v0.3 진행 중.
//

import AppKit
import Foundation

/// LLM 호출 전 routing decision.
enum LLMRoutingDecision: Sendable, Equatable {
    case cloud                              // 일반 화면 — 기존 cloud dispatcher
    case localOnly                          // 민감 화면 — local LLM (Qwen) 사용
    case blockedLocalModelNotInstalled      // 민감 화면 + local 미설치 — *차단* + alert
}

enum SensitivityRouter {

    /// Hardcoded deny-list — *민감 정보 포함 가능성 큰* 앱 bundle ID.
    /// 사용자가 *명시적 인지* 가능한 카테고리만:
    ///   비밀번호 관리 / 한국 은행 / 한국 신용카드 / Mail compose / 메시지 일부.
    ///
    /// 추가/제거는 *enterprise admin*이 plist/MDM으로 갱신 가능 (v0.4 박을 거).
    /// 현재는 hardcoded. 사용자가 명시적 opt-in/opt-out 시 추후 setting 박음.
    static let denyList: Set<String> = [
        // === 비밀번호 관리 ===
        "com.agilebits.onepassword7",        // 1Password 7
        "com.1password.1password",            // 1Password 8
        "com.bitwarden.desktop",              // Bitwarden
        "com.apple.keychainaccess",           // Keychain Access
        "com.lastpass.LastPass",              // LastPass

        // === 한국 은행 ===
        "com.kakaobank.kbankapp",             // 카카오뱅크
        "com.kbstar.smartbank",               // KB국민
        "com.shinhan.smartbank",              // 신한
        "com.hanafn.hana1q",                  // 하나
        "com.wooribank.smart",                // 우리
        "com.nh.smartbank",                   // 농협
        "viva.republica.toss",                // 토스

        // === 한국 신용카드 ===
        "com.shinhancard.SHC",                // 신한카드
        "com.bccard.BCCard",                  // BC카드
        "com.samsungcard.SamsungCard",        // 삼성카드
        "com.hyundaicard.MOSAIC",             // 현대카드

        // === Mail compose (전체 Mail.app — compose window 분리는 v0.4) ===
        "com.apple.mail",                     // Apple Mail (compose detect 박는 게 v0.4)
    ]

    /// 현재 frontmost app의 bundleID로 routing decision 박음.
    ///
    /// - Parameters:
    ///   - frontmostBundleID: 사용자가 본 화면의 앱 bundle ID (NSWorkspace 또는 capture meta).
    ///   - localModelAvailable: Qwen local model 박혔는지 (v0.2 false / v0.3+ true).
    static func decide(
        frontmostBundleID: String?,
        localModelAvailable: Bool = false
    ) -> LLMRoutingDecision {
        guard let id = frontmostBundleID else {
            // bundleID 못 얻으면 — 안전쪽으로 cloud (현재 사용자 환경 가정)
            return .cloud
        }
        let isSensitive = denyList.contains(id)
        if isSensitive {
            return localModelAvailable ? .localOnly : .blockedLocalModelNotInstalled
        }
        return .cloud
    }

    /// macOS NSWorkspace에서 *지금* frontmost app bundle ID 가져옴. main actor isolated.
    @MainActor
    static func currentFrontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

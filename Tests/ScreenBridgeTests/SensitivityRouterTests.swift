//
//  SensitivityRouterTests.swift
//  ScreenBridgeTests — v0.3 Layer 2
//

import Foundation
import Testing
@testable import ScreenBridge

@Suite("v0.3 Layer 2 — SensitivityRouter.decide")
struct SensitivityRouterTests {

    @Test("nil bundleID → .cloud (안전 default)")
    func nilBundleID() {
        #expect(SensitivityRouter.decide(frontmostBundleID: nil) == .cloud)
    }

    @Test("일반 앱 (Chrome) → .cloud")
    func normalApp() {
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.google.Chrome") == .cloud)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.apple.Safari") == .cloud)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.tinyspeck.slackmacgap") == .cloud)
    }

    @Test("1Password (v0.2 — Qwen 미설치) → .blockedLocalModelNotInstalled")
    func passwordManagerBlocked() {
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.agilebits.onepassword7", localModelAvailable: false) == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.1password.1password", localModelAvailable: false) == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.bitwarden.desktop", localModelAvailable: false) == .blockedLocalModelNotInstalled)
    }

    @Test("1Password (v0.3+ Qwen 박힘) → .localOnly")
    func passwordManagerLocal() {
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.agilebits.onepassword7", localModelAvailable: true) == .localOnly)
    }

    @Test("카카오뱅크 / Toss / 신한 → blocked (v0.2)")
    func koreanBankingBlocked() {
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.kakaobank.kbankapp") == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "viva.republica.toss") == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.shinhan.smartbank") == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.kbstar.smartbank") == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.hanafn.hana1q") == .blockedLocalModelNotInstalled)
    }

    @Test("한국 신용카드 앱 → blocked")
    func koreanCreditCardBlocked() {
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.shinhancard.SHC") == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.bccard.BCCard") == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.samsungcard.SamsungCard") == .blockedLocalModelNotInstalled)
    }

    @Test("KeychainAccess / Mail → blocked")
    func systemAppsBlocked() {
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.apple.keychainaccess") == .blockedLocalModelNotInstalled)
        #expect(SensitivityRouter.decide(frontmostBundleID: "com.apple.mail") == .blockedLocalModelNotInstalled)
    }

    @Test("denyList 13+ entries 박힘 (v0.3 starter)")
    func denyListSize() {
        #expect(SensitivityRouter.denyList.count >= 13)
    }

    @Test("denyList 한국 은행 7개 박힘 (카뱅 + 국민/신한/하나/우리/농협/토스)")
    func koreanBanksCovered() {
        let banks = ["com.kakaobank.kbankapp", "com.kbstar.smartbank",
                     "com.shinhan.smartbank", "com.hanafn.hana1q",
                     "com.wooribank.smart", "com.nh.smartbank",
                     "viva.republica.toss"]
        for bank in banks {
            #expect(SensitivityRouter.denyList.contains(bank))
        }
    }
}

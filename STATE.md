# Current State

**Stack:** Swift macOS native (SwiftUI + AppKit). Tauri v0.1 attempt는 `tauri-archive` branch + `v0.1-tauri-attempt` tag로 보존.

**Phase:** Swift 0.1 — SwiftPM scaffold
**Last completed:** SwiftPM executable package + macOS 14 platform + 기본 SwiftUI App + `swift build` 통과 (9.37s).
**Last commit:** 32929bd (main reset — Tauri 제거)
**Next step:** Phase 0.2 Swift — AppDelegate (NSApplicationDelegateAdaptor) + LSUIElement (menu bar only) + NSStatusItem tray.
**Blockers:** 없음. Swift 6.3.2 + Xcode 26 + macOS 26 (Tahoe) 환경 정상.
**Last updated:** 2026-05-27T19:20:00Z

## Swift Phase 매트릭스 (간단, 풀 SPEC update 별도)

- [x] Phase 0.1 SwiftPM scaffold (이 commit)
- [ ] Phase 0.2 AppDelegate + LSUIElement + NSStatusItem (menu bar)
- [ ] Phase 0.3 Info.plist + Entitlements (Accessibility, Screen Recording 권한)
- [ ] Phase 0.4 .env loading
- [ ] Phase 1.1 logging (os_log + logs/build.log)
- [ ] Phase 1.2 fixture loader (Codable)
- [ ] Phase 1.3 config (Keychain or .env)
- [ ] Phase 2.1 prompts (constant — SPEC SYSTEM_PROMPT 그대로)
- [ ] Phase 2.2 LLMDispatcher protocol
- [ ] Phase 2.3 GeminiDispatcher (URLSession, responseSchema 강제)
- [ ] Phase 2.4 fixture tests (XCTest)
- [ ] Phase 3.1 ScreenCaptureKit (multi-monitor + DPR 자동)
- [ ] Phase 3.2 Carbon RegisterEventHotKey ⌥+Space
- [ ] Phase 3.3 NSStatusItem 메뉴 (Trigger / Open sessions / Quit)
- [ ] Phase 4.1 NSWindow trigger panel (SwiftUI content)
- [ ] Phase 4.2 analyze flow (async/await)
- [ ] Phase 5.1 NSWindow HUD overlay (.collectionBehavior + ignoresMouseEvents)
- [ ] Phase 5.2 overlay content (RedBoxView + BubbleView, SwiftUI)
- [ ] Phase 5.3 trigger → overlay flow
- [ ] Phase 6.1 AXUIElement OR Vision framework OCR (deterministic 좌표)
- [ ] Phase 6.2 sessions (FileManager + ~/Library/Application Support)
- [ ] Phase 6.3 feedback meta
- [ ] Phase 6.4 settings UI

## v0.1 Tauri attempt 완료 결과

- Phase 0-6 코드 완성: 30+ commits, BUILD_REPORT.md 참조
- 발견 후 미해결로 남긴 layer 16개 (PROJECT_TIMELINE.md)
- 사용자 명시 "냉정하게 사용성 최대화" → Swift swap 결정 (DECISIONS.md "STACK SWAP")

## SCRATCHPAD 미해결: 4
- git pre-commit hook portable X (`.git/` untracked)
- macocr 설치 권유 (Tauri stack 한정 — Swift엔 Vision framework 직접)
- Phase 6.3 Settings minimal (Swift에선 v0.2)
- Phase 3.1 Screen Recording 권한 (Swift Info.plist에 NSScreenCaptureUsageDescription)

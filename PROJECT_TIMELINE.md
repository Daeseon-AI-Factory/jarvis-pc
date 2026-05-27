# PROJECT TIMELINE

ScreenBridge 전체 history. 각 phase별 무엇을 결정했고 왜 그쪽으로 갔는지. CLAUDE.md / SPEC.md / PRODUCT.md는 *현재 룰*이지만 이 파일은 *왜 그 룰에 도달했는지의 흔적*.

새 결정 / phase 전환 / stack swap 시 즉시 append. 사후 정리 금지 (R8 정신).

---

## 2026-05-26 — v0.1 시작 (Tauri stack)

**결정:** PRODUCT.md / SPEC.md / CLAUDE.md 작성. stack = Tauri 2.0 + Rust + React/TS + Anthropic API.

**근거 (당시):**
- Rust 학습
- React/TS frontend 익숙
- Cross-platform 옵션 보존 (미래 Windows/Linux)
- Electron 대비 가벼움 (메모리/번들)
- v0.7+ LLM Sovereignty (로컬 모델) trajectory와 잘 맞음

**Phase 0-6 진행** (Tauri 셸 셋업 → dispatcher → capture → hotkey → tray → trigger panel → overlay → sessions → polish). 26 commits. v0.1 코드 차원 완성. `BUILD_REPORT.md` 참조.

---

## 2026-05-26~27 — Tauri stack의 macOS HUD 한계 발견

dogfooding 진입 시도 중 발견한 layer들 — *모두 macOS-native HUD 앱에선 SDK가 한 줄로 해결하는 것을 Tauri 추상화 위에 재발견*. 시간순:

| 시점 | 발견 | macOS native 표준 |
| --- | --- | --- |
| 22:10 | `visible:false` + `fullscreen:true` + `transparent` 충돌 | NSWindow `.isOpaque=false` + `.backgroundColor=.clear` 두 줄 |
| 22:15 | capability `windows:["main"]`이 새 라벨 안 잡음 (silent fail) | NSWindow 자체에 권한 없음 — Apple SDK 직접 호출 |
| 22:18 | `core:default`가 `window.show` 자동 미포함 | NSWindow.makeKeyAndOrderFront 직접 호출 |
| 23:00 | transparent + macOSPrivateApi feature 둘 다 필요 | NSWindow native opacity 표준 |
| 23:10 | Groq vision 검색 결과 모순 → 공식 docs 직접 확인 | (vendor 무관, WebFetch 학습) |
| 23:30 | claude CLI subprocess silent fail (env 인증 conflict) | (vendor 무관) |
| 23:50 | DPR 4-layer 좌표 변환 (capture physical → 다운스케일 → monitor physical → CSS logical) | NSScreen `.convertRect(from:)` 한 함수 |
| 24:00 | visibleOnAllWorkspaces:true 부작용 | NSWindow `.collectionBehavior = [.moveToActiveSpace]` |
| 19:00 | overlay 클릭 차단 → click-through 필요 | NSWindow `.ignoresMouseEvents = true` |
| 19:15 | overlay webview 흰색 가림 (CSS :root background) | (Tauri/WebView 고유 문제) |
| 19:30 | Gemini free-form 응답 → responseSchema 강제 | (vendor 무관) |
| 19:45 | reqwest default timeout 없음 → 3분 hang | (Rust HTTP 클라이언트 패턴) |
| 20:00 | LLM 좌표 추정 정확도 70% → OCR + element matching | AXUIElement (Accessibility) ~100% |
| 20:15 | OCR architecture 결정 (macocr subprocess) | macocr CLI / 또는 VNRecognizeTextRequest 직접 |
| 20:30 | multi-monitor — primary monitor만 캡처 (사용자가 본 화면 아님) | NSScreen.screens + NSEvent.mouseLocation |
| 20:45 | analyze 시점 cursor가 panel monitor로 이동 → trigger 시점 cursor 기록 필요 | (intent signal 분리, 일반 패턴) |

총 16 layer 발견. 각각 Tauri 추상화 우회로 매번 1-2 commit.

`TROUBLESHOOTING.md` 모든 entry + `DECISIONS.md` matrix 모두 학습 자산. macOS HUD app의 *어디가 함정인지* 영구 기록.

---

## 2026-05-27 — Tauri → Swift native 결정

**문제 인식:**
- dogfooding 진입까지 매 layer trial-and-error
- product 본질 = macOS HUD overlay = native가 표준 패턴
- 사용자 명시: "냉정하게 사용성 최대화"
- Tauri는 cross-platform desktop framework — *macOS native HUD 카테고리에 mismatch*

**옵션 검토** (DECISIONS.md "Swift native vs Tauri" entry):
- A. Tauri 그대로 → 발견한 layer는 다 박혔지만 추가 feature마다 또 발견
- **B. Swift native rewrite** ← 채택
- C. Tauri + 점진적 native (objc2)

**B 선택 근거:**
- macOS HUD = Apple SDK의 표준 use case. AXUIElement / ScreenCaptureKit / NSWindow.collectionBehavior 모두 SDK 표준.
- 좌표 정확도 — AXUIElement = ~99-100% (OCR + LLM matching ~95-99% 대비 한 단계 ↑)
- 개발 속도 — SDK 한 줄씩 vs Tauri 추상화 우회 매번
- 학습 자산 보존 — TROUBLESHOOTING/DECISIONS는 stack 무관 transferable

**비용:**
- Tauri 코드 ~3000줄 / 30 commits sunk (학습 가치 보존)
- 1-2주 rewrite
- cross-platform 포기 (macOS only)

**백업 + 보존:**
- `git tag v0.1-tauri-attempt` (영구 마커)
- `git branch tauri-archive` (Tauri 코드 영구 보존)
- 둘 다 origin에 push 완료
- 학습 자산 (`TROUBLESHOOTING.md`, `DECISIONS.md`, `SCRATCHPAD.md`, `PRODUCT.md`, `SPEC.md`)는 main에서 그대로 가져감

---

## 2026-05-27 onwards — v0.2 (Swift native)

진행 예정:
- Xcode macOS App project (SwiftUI + AppKit)
- NSWindow native HUD (transparent + click-through + collectionBehavior)
- ScreenCaptureKit (capture)
- AXUIElement (UI element list — vision LLM은 element label만, 좌표는 AX)
- Vision framework VNRecognizeTextRequest (OCR fallback)
- Anthropic SDK (또는 URLSession) — SPEC SYSTEM_PROMPT 그대로
- Carbon global hotkey
- NSStatusItem tray

PRODUCT.md / SPEC.md 본질은 그대로. stack만 swap. Tauri-specific 룰들 (capability, visibleOnAllWorkspaces, macos-private-api 등)은 자연스럽게 사라짐.

다음 timeline entry는 SwiftUI project 첫 commit 시점.

---

## 2026-05-27 — main 정리: Tauri 코드 → `tauri-archive` branch에만

옵션 A (DECISIONS.md "STACK SWAP" 참조) 채택. main에서 Tauri-specific 파일 제거:
- `src/` (React frontend)
- `src-tauri/` (Rust backend + Cargo.toml + capabilities)
- `package.json`, `package-lock.json`, `index.html`, `vite.config.ts`, `tsconfig*.json`, `public/` (Vite/Node)

보존 (학습 자산 + stack 무관 meta):
- 룰 문서: PRODUCT.md, SPEC.md (update 예정), CLAUDE.md, STATE.md, SCRATCHPAD.md
- 학습 자산: TROUBLESHOOTING.md, DECISIONS.md, PROJECT_TIMELINE.md, BUILD_REPORT.md
- Asset: fixtures/, logs/build.log, scripts/verify_key.sh, .env, .claude/settings.json (hook), .git/hooks/pre-commit

`.gitignore` Swift/Xcode 친화로 update — node_modules / target / dist 제거, DerivedData / xcuserdata / .swiftpm / build 추가.

Tauri 코드 복원 방법 (필요 시):
- `git checkout tauri-archive` (전체)
- 또는 `git checkout v0.1-tauri-attempt -- <path>` (일부)
- GitHub UI: https://github.com/Daeseon-AI-Factory/jarvis-pc/tree/tauri-archive

다음 commit: Xcode project scaffold (사용자가 Xcode에서 새 macOS App 생성 후).

---

## 2026-05-27 — Swift Phase 0.1: SwiftPM scaffold

옵션 B 채택 (SwiftPM via `swift package init --type executable`). root에 `Package.swift` + `Sources/ScreenBridge/ScreenBridgeApp.swift`. 사용자 Xcode GUI 없이 cargo-style CLI 사이클 (`swift build` / `swift run`).

- `Package.swift`: macOS 14+ platform, Swift 6 language mode.
- `Sources/ScreenBridge/ScreenBridgeApp.swift`: 기본 SwiftUI `@main App` + `ContentView` placeholder.
- `swift build` 9.37s 통과.
- Tests/ScreenBridgeTests/ stub.

다음 (Swift 0.2): NSApplicationDelegateAdaptor + LSUIElement (Info.plist) + NSStatusItem.

production `.app` bundle은 후속 (`swift-bundler` 또는 Xcode build phase). 일단 dev = `swift run`.

---

(append-only — 각 phase / stack swap / 큰 결정 즉시 추가. 사후 정리 금지.)

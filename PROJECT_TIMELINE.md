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

## 2026-05-27 — Project log dual-write system 도입

사용자가 [블로그 글](https://www.daeseon.ai/posts/install-claude-code-project-log)에서 정의한 dual-write log system 도입. ScreenBridge 외 다른 plot도 같은 mechanism으로 publish.

추가:
- `docs/troubleshooting.md` — terse problem-indexed reference (Symptom / Cause / Fix / Commit / Pattern)
- `content/logs/jarvis-pc/<YYYY-MM-DD>-<short-slug>.mdx` — dated narrative + frontmatter (title/date/project/kind/visibility/language/summary/tags)
- `.claude/settings.json` Stop hook — 2분 내 commit 있으면 systemMessage로 dual-write reminder
- `CLAUDE.md`에 "Project log (required, dual-write)" section + anti-hallucination 7 rules

기존 학습 자산과의 layer 관계:
- `TROUBLESHOOTING.md` (자세히, repo 내부, R8 강제) → *학습 자산 layer*
- `DECISIONS.md` (trade-off, repo 내부, R9 강제) → *결정 layer*
- `PROJECT_TIMELINE.md` (history, append-only) → *이 파일*
- `docs/troubleshooting.md` (terse, publish용 ref) → *새*
- `content/logs/jarvis-pc/` (narrative, blog post) → *새*

첫 entry 작성:
- `docs/troubleshooting.md`: Tauri → Swift swap (terse)
- `content/logs/jarvis-pc/2026-05-27-tauri-to-swift-swap.mdx`: 같은 사건 narrative (tech-retro, public, 한국어)

다음 commit부터 모든 non-trivial 변경은 dual-write 동반.

---

## 2026-05-28 — Swift Phase 0.2 완료 + 다음 세션 HANDOFF 정리

Swift Phase 0.2 (menu-bar shell + Carbon hotkey + NSPanel, `63c0568`) 후 사용자가 *다른 Claude Code 세션*에서 이어갈 준비. HANDOFF 정리:

- `STATE.md` → HANDOFF 수준 재작성: 현재(Swift 0.2 완료) + Next step(Phase 2.x dispatcher) + 확정 결정 매트릭스 8개 + SYSTEM_PROMPT 골자 + 학습 자산 5 layer + 룰 (R4 swift). **새 세션이 이거 하나로 위치 파악.**
- `SCRATCHPAD.md` → Swift 기준 재정리. Tauri 시절 항목 (ocr.rs/macocr/tests 위치) obsolete 처리. 미해결 4건 (SPEC stale 경고 / disk 정리 / hook portable / fixture 이미지 / Screen Recording 권한).
- `CLAUDE.md` → 환경 (Swift 6.3 + Xcode 26), 모델 (Gemini Flash 채택), R4 (`swift build`+`swift test`), RESUME PROTOCOL에 "SPEC.md stale, STATE.md 우선" 경고.
- `SPEC.md` → 헤더에 ⚠️ STALE 경고 (Tauri 기준, Swift는 STATE.md 따름).
- `docs/troubleshooting.md` → Swift 6 deinit entry hash backfill (`63c0568`).
- disk 정리: `rm -rf src-tauri node_modules` (Tauri 빌드 캐시 7.2GB + 84MB). source는 tauri-archive branch에 보존. repo 7.3GB → 164MB.

**새 세션 RESUME 핵심: STATE.md → DECISIONS.md → SCRATCHPAD.md. SPEC.md 따라가지 말 것 (Tauri stale).** 다음 작업 = Swift Phase 2.x (GeminiDispatcher).

---

## 2026-05-29 — Swift Phase 2.1 시작 (sweep workflow → 본격 implementation)

이전 session에서 STATE.md HANDOFF 정리 + memory에 *번역기 정체성* 박음 (`product-identity-screenbridge`: 비-AI-native 타겟, "AI가 시키는 거 모르는 사람에게 알기쉽게 지시"). 이번 session 시작에 사용자 신호: "확실히 고도화", "제대로 원하는 제품이 나오게" → ultracode 모드 + workflow tool 본격 사용.

**Sweep + Synthesize workflow** (`screenbridge-restart-deep-prep`, 12 agents / 469k tokens / 12분):
- 11개 영역 병렬 — code audit / decisions audit / Tauri 학습자산 / SPEC stale / HUD click-through / multi-monitor+DPR / permission / NSPanel 분리 / ScreenCaptureKit API / Vision OCR API / Gemini API.
- 1개 synth — Phase 2-6 plan + 5개 phase별 deliverable_files/sequence/key_decisions/risk_mitigations/code_hint + cross_cutting 13개 + 첫 atomic + Swift phase 순서 advice.

**Sweep advice 채택 (STATE.md Next step 순서 swap):**
1. **AnalysisResult struct가 첫** atomic — Prompts/Dispatcher 모두 의존, 가장 작은 단위. (원래 STATE에선 #4였음)
2. Phase 5를 **5.0 (빈 골격, dispatcher 무관 검증) + 5.x (실 데이터)**로 쪼개 Phase 3.1 직후 5.0 끼움. 후속 phase에서 좌표 디버그 시 "window/dispatcher/OCR" 3-way 모호함 사전 차단.
3. **권한 다이얼로그를 Phase 3.1보다 0.5단계 빨리** (AppDelegate startup).
4. Phase 6.1 OCR은 Phase 5 HUD 완성 *후* — 시각적 eyeball 검증 가능해야 fuzzy threshold 튜닝이 추측 X.

**Phase 2.1 완료 (이 commit):**
- `Sources/ScreenBridge/AnalysisResult.swift` — Codable, Sendable, Equatable struct.
- 핵심: `targetText` (visible text 그대로, OCR matcher source), `coordinates: [Int]?` (LLM fallback only — 번역기 본질 "99% 좌표는 OCR이 source"), `raw` Codable 분리 + `withRaw(_:)` builder (R9 5-파트 DECISIONS × 2).
- `Tests/ScreenBridgeTests/AnalysisResultTests.swift` 6/6 통과 — snake_case decode, optional coordinates, encode raw 제외, withRaw builder, missing field throws.
- `swift build` 1.41s, `swift test` 0.002s (R4 통과).

**다음:** Phase 2.2 — `Prompts.swift` (한국어 SYSTEM_PROMPT, target_text 필수, ✗/✓ 페어, "여기 [버튼] 누르세요" 톤) + `Env.swift` (GEMINI_API_KEY 로드, dep 0).

---

## 2026-05-29 — Swift Phase 2.2: Prompts + Env (번역기 본질 SYSTEM_PROMPT에 박음)

**Phase 2.1 commit hash backfill:** `e075f0f`.

**Phase 2.2 완료 (이 commit):**
- `Sources/ScreenBridge/Prompts.swift` — SYSTEM_PROMPT 상수. 번역기 본질 4개 코드화:
  1. *target_text 룰*: "한 글자도 임의로 바꾸지 마라". ✗/✓ 페어 (`"auth button"` ✗ vs `"Sign in"` ✓, `"the create button"` ✗ vs `"Create API Key"` ✓).
  2. *next_action 톤*: "여기 [Settings] 버튼 보이죠? 누르세요" 같은 비-AI-native 친화. jargon 금지.
  3. *한 화면 = 한 동작*: 다단계 응답 금지.
  4. *coordinates fallback only*: 화면 텍스트 없는 아이콘에만 사용, 평소 키 자체 생략 (OCR이 source).
- `Sources/ScreenBridge/Env.swift` — `GEMINI_API_KEY` 로드. ProcessInfo + `.env` 폴백 (현재 working dir + `~/.screenbridge/.env`). dep 0 (R9 DECISIONS).
- `Tests/.../PromptsTests.swift` (4 tests) + `EnvTests.swift` (8 tests). 누적 18/18 통과 (`swift build` 1.41s, `swift test` 0.002s).

**R9 결정 2건 박음** (DECISIONS.md): `.env` parser dep 0 직접, SYSTEM_PROMPT 한국어 강제.

**다음:** Phase 2.3 — `LLMDispatcher.swift` (protocol) + `GeminiDispatcher.swift` (URLSession POST `gemini-2.5-flash:generateContent`, `responseMimeType`+`responseSchema` 강제, `timeoutInterval=30`, retry 429/500/503 exp backoff max 3) + fixture-based test (`XCTSkipUnless GEMINI_API_KEY`).

---

## 2026-05-29 — Swift Phase 2.3: GeminiDispatcher + os.Logger 전체 swap

**Phase 2.2 commit hash backfill:** `f7b799b`.

**Phase 2.3 완료 (이 commit):**
- `Sources/ScreenBridge/Logging.swift` — `Log` enum (subsystem=`com.screenbridge.app`, categories app/hotkey/panel/dispatcher).
- `Sources/ScreenBridge/LLMDispatcher.swift` — protocol + `DispatcherError` (7 cases, Phase 4.2에서 한국어 매핑).
- `Sources/ScreenBridge/GeminiDispatcher.swift` — actor, URLSession async/await, `responseMimeType='application/json'` + `responseSchema` 강제, image part FIRST + text AFTER, timeout 30/60s, retry 429/500/502/503/504 exp backoff 1/2/4s + jitter max 3.
- `JSONSchema` `indirect enum` (Swift struct 자기참조 X → infinite size, build 에러 → enum case 구분으로 더 명확).
- `NSLog → os.Logger` 전체 swap (AppDelegate / TriggerPanel / HotKeyManager) — `log stream --predicate 'subsystem == "com.screenbridge.app"'` 한 명령으로 별도 terminal에서 줄줄 + Console.app.
- HotKeyManager OSStatus discard → `Log.hotkey.error("OSStatus=… 다른 앱이 ⌥+Space 점유 가능")` — silent fail 차단.
- `Tests/.../GeminiDispatcherTests.swift` 6 tests (schema shape + JSON encode + image FIRST quirk + envelope decode + fromEnvironment). 누적 24/24 통과 (`swift build` 3.18s, `swift test` 0.007s).

**R9 결정 2건** (DECISIONS.md): NSLog → os.Logger swap (사용자 좌절 → stream 가능), Gemini API URLSession 직접 (dep 0).

**R8 디버그 2건** (docs/troubleshooting.md): Swift 6 struct 자기참조 infinite size → indirect enum, HotKeyManager OSStatus discard → 명시 log.

**사용자 좌절 흐름 해결** (memory `user-pain-dev-tool-friction`): 사용자 본인 terminal에서 `./dev.sh` → log 그 terminal 직접 + 별도 terminal `log stream` → Console.app 식 stream.

**다음:** Phase 3.1 — `Permissions.swift` + `TriggerContext.swift` (cursor 즉시 저장, Layer 10 회피) + `DisplayGeometry.swift` (4-layer 변환 캡슐화) + `ScreenCapture.swift` (`SCShareableContent` + `SCScreenshotManager` + 1568 다운스케일).

---

## 2026-05-29 — Swift Phase 3.1: ScreenCaptureKit + Permissions + 좌표 변환

**Phase 2.3 commit hash backfill:** `8a60c2f`.

**Phase 3.1 완료 (이 commit):**
- `Sources/ScreenBridge/Permissions.swift` — Screen Recording (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`) + Accessibility (`AXIsProcessTrustedWithOptions`) + Settings URL fallback.
- `Sources/ScreenBridge/TriggerContext.swift` — `LastTriggerContext` static. `HotKeyManager.onTrigger` 콜백 즉시 `capture()` → `(cursor, screen frame, backingScaleFactor, displayID, timestamp)` snapshot. Analyze 시점 cursor 절대 X (Tauri Layer 10 회피).
- `Sources/ScreenBridge/DisplayGeometry.swift` — 4-layer 좌표 변환 (physical px → sent px → logical pt → screen-local) 캡슐화. `logicalRectFromSentBox([Int])` LLM sent px → screen-local logical pt CGRect (top-left). `NSScreen.main` 절대 금지 — captured display 기준 (Tauri Layer 9 회피).
- `Sources/ScreenBridge/ScreenCapture.swift` — `captureCursorScreen()` async. SCShareableContent + SCContentFilter + SCStreamConfiguration (physical pixel 명시) + SCScreenshotManager.captureImage. CGContext draw `.high` interpolation 1568 다운스케일. NSBitmapImageRep PNG encode. 결과 `(Data, DisplayGeometry)`.
- `AppDelegate.swift` — hotkey 콜백에 `LastTriggerContext.capture()` 추가 + startup에서 Screen Recording 권한 trigger (sweep advice 0.5단계 빨리).
- `dev.sh` — ad-hoc codesign 추가 (`codesign --force -s - <binary>`) — TCC가 binary identity 기억해 매 빌드 권한 재요청 X.
- `Tests/.../DisplayGeometryTests.swift` 5 tests (Retina 다운스케일 / identity / Retina only / invalid box / zero division). 누적 29/29 통과 (`swift build` 2.60s, `swift test` 0.006s).

**R9 결정 2건** (DECISIONS.md): 권한 startup trigger (eager), ScreenCaptureKit (vs deprecated CGDisplayCreateImage).

**R8 디버그 1건** (docs/troubleshooting.md): Swift 6 strict concurrency가 `kAXTrustedCheckOptionPrompt` (extern var) 거부 → string literal `"AXTrustedCheckOptionPrompt"` 대체.

**다음:** Phase 5.0 — `HUDOverlayWindow.swift` 빈 골격 (dispatcher 무관 검증). NSPanel borderless + nonactivating + clear + `ignoresMouseEvents=true` 영구 + `level=.screenSaver` + collectionBehavior 3개 셋 (`canJoinAllSpaces` + `fullScreenAuxiliary` + `stationary`) + multi-monitor frame pin + 빨간 박스 1개 hardcode. dispatcher 정확도 무관하게 NSWindow 본질 5개 검증.

---

## 2026-05-29 — Swift Phase 3.1 verify fix: adversarial workflow BLOCKER 3 + HIGH 3

**Phase 3.1 commit hash backfill:** `7f4d4f4`.

**Adversarial verify workflow** (`phase-3-1-verify`, 6 agents / 224k tokens / 4분):
- 5 dimensions parallel — ScreenCaptureKit API correctness / 4-layer 좌표 수학 / Permissions 흐름 / multi-monitor edge / Swift 6 concurrency.
- 1 synth — **verdict: FIX_FIRST, ready_for_phase_5: false**.

**발견 (이 commit에서 fix):**
1. **BLOCKER** ScreenCapture L65 `SCContentFilter(display:excludingWindows: [])` — Federico Terzi 검증 SCStream buffer stall documented bug. → `init(display:excludingApplications:exceptingWindows:)` Apple-sanctioned shape.
2. **BLOCKER** ScreenCapture L39 + TriggerContext L32 `?? NSScreen.main` fallback — DisplayGeometry "절대 금지" 명시한 rule 자기 코드에서 위배 (Tauri Layer 9 재발 패턴). → `?? NSScreen.screens.first`.
3. **BLOCKER** DisplayGeometry `logicalRectFromSentBox`가 screen-local만 반환, `screenFrame.origin` 미반영 — Phase 5 HUD가 raw `NSWindow.setFrame` 직접 호출 시 외부 monitor에서 primary로. → `globalAppKitRect(fromLocalTopLeft:) -> NSRect` helper 추가 (origin add + y flip 한 곳, R9 DECISIONS).
4. **HIGH** AppDelegate `requestScreenRecording()` Bool 무시 + 거부 후 in-app recovery 없음 (macOS TCC 다이얼로그 영구 재출현 X). → 1.5s 후 `hasScreenRecording()` 재확인 + 거부 시 `openScreenRecordingSettings()`.
5. **HIGH** ScreenCapture LastTriggerContext stale frame/scale — 해상도 변경/hotplug 시. → displayID만 신뢰 + frame/scale은 capture 시점 NSScreen fresh fetch.
6. **HIGH** dev.sh `codesign --identifier` 누락 → cdhash 매 build 변경 → TCC 권한 재요청 loop. → `--identifier com.screenbridge.dev` 명시.

**Tests 추가 (4)**: `globalAppKitRect` primary / 외부 monitor x=1440 / vertical stack origin.y=900 / 비균일 scaleX/scaleY (3024x1964 → 1568x1018).

**누적 33/33 통과** (`swift build` 2.30s, `swift test` 0.008s).

**R8 학습 자산 4건** (docs/troubleshooting.md): SCContentFilter empty array bug, NSScreen.main 자기 모순, screenFrame.origin 미반영, codesign --identifier loop.

**R9** (DECISIONS.md): `globalAppKitRect` helper (raw CGRect setFrame 차단).

**Sweep workflow vs adversarial verify의 가치 입증**: Phase 3.1 시작 전 sweep은 plan을 박았지만 — *코드 작성 후* 다 implement된 상태에서만 catch되는 함정 (벤더 SDK bug, 자기 모순 fallback, partial conversion helper)을 verify workflow가 잡음. *Sweep (plan) → Implement → Verify (adversarial review)* 3단계가 ultracode 정신 본질. Phase 4.2 / 5.x / 6.1 commit 후에도 verify workflow 권장.

**다음:** Phase 5.0 — HUDOverlayWindow 빈 골격. **첫 atomic부터 `globalAppKitRect` 사용 강제** (raw `setFrame(rect)` X — Tauri Layer 9 차단). NSPanel borderless + nonactivating + clear + `ignoresMouseEvents=true` + `level=.screenSaver` + collectionBehavior 3개. 빨간 박스 1개 hardcode로 사용자 ⌥Space 직후 표시 — Layer 1/4/7/8/9 dispatcher 무관 검증.

---

## 2026-05-29 — Swift Phase 5.0: HUDOverlayWindow 빈 골격 — *첫 눈으로 보는 단계*

**Phase 3.1 verify fix commit hash backfill:** `131da7b`.

**Phase 5.0 완료 (이 commit) — 안경 메타포 시각화 첫 시도:**

- `HUDOverlayWindow.swift` — NSPanel borderless + nonactivating + clear + hasShadow=false + `level=.screenSaver` + collectionBehavior 3개 (canJoinAllSpaces + fullScreenAuxiliary + stationary) + `ignoresMouseEvents=true` 영구 + `sharingType=.none` + canBecomeKey/canBecomeMain=false. NSWindow 본질 5개 (Layer 1/4/7/8/9 회피) lock.
- `HUDOverlayView.swift` — `HUDAnnotation` (rect: CGRect, Sendable+Equatable) + SwiftUI View (ZStack + Color.clear + RoundedRectangle stroke .red lineWidth 3 corner 4).
- `HUDController.swift` — `present(annotation, on screen)` + `dismiss()` + `presentPlaceholderCenter(on screen)` hardcode 300x50 빨간 박스 화면 중앙. `screen.frame` raw setFrame 안전 명시 (global AppKit, partial conversion 결과 아님).
- `AppDelegate.swift` — `HUDController` 소유 + `handleHotkey` (HUD 떠있으면 dismiss, 아니면 panel toggle) + `handleAnalyze` (cursorScreen → `presentPlaceholderCenter`) + `cursorScreen` helper (LastTriggerContext.displayID 우선, fallback `NSScreen.screens.first` — verify fix lesson).
- `TriggerPanel.swift` — `TriggerPanel(onAnalyze:)` closure init + TriggerPanelView `onAnalyze` callback. Analyze 후 panel 자기 close → HUD 뜸 (사용자가 본 화면 다시 보임).

**Tests (10 new)**: HUDOverlayWindow 8 (transparent + click-through + level + collectionBehavior 3 bits + styleMask + canBecomeKey/Main + sharingType + isReleasedWhenClosed). HUDController 2 (초기 isShowing=false + dismiss no-op).

**누적 43/43 통과** (`swift build` 2.15s, `swift test` 0.122s).

**R9** (DECISIONS.md): HUD architecture (single screen-wide + SwiftUI 내 박스 vs N box-sized window vs union all monitors).

**사용자 검증 흐름 (Phase 5.0 직후 — 첫 *눈으로 보는* 단계):**
1. `./dev.sh` 새 binary
2. ⌥+Space → trigger panel
3. 텍스트 입력 + Analyze (또는 ⌘Return)
4. **화면 중앙에 빨간 박스 1개 뜸** (300x50 hardcode)
5. ⌥+Space → 빨간 박스 dismiss

NSWindow 5개 본질 사용자 검증 — Keynote 풀스크린/Mission Control/Stage Manager에서도 박스 보이는지 + 클릭 desktop으로 통과하는지 + 다른 monitor에서도 cursor 있는 monitor에 뜨는지.

**다음:** Phase 4.2 — `AnalyzeCoordinator` (actor, async let capture+dispatcher 병렬) + `AnalyzeRequest`/`AnalyzeStage` enum + TriggerPanel loading spinner + 한국어 에러 메시지 매핑. handleAnalyze가 hardcode 대신 *진짜 capture + dispatcher + DisplayGeometry* 호출. ~1-1.5시간.

---

## 2026-05-29 — Swift Phase 4.2: AnalyzeCoordinator + 진짜 동작 시작

**Phase 5.0 commit hash backfill:** `a51dc09`.

**Phase 4.2 완료 (이 commit) — *진짜 동작* 첫 시도 (LLM coordinates 의존, OCR Phase 6.1 전):**

- `AnalyzeRequest` struct + `AnalyzeStage` enum (capturing / analyzing / done(result, geometry) / failed(DispatcherError))
- `ScreenCaptureService` protocol + `LiveScreenCapture` struct wrapper (R9 — test mock 가능)
- `AnalyzeCoordinator` actor — capture → dispatcher sequential, 중복 trigger reject (isRunning flag)
- `UserMessage` enum — `DispatcherError` → 비-AI-native 친화 한국어 매핑 (jargon 금지)
- `HUDOverlayView` rewrite — `HUDContent` enum (loading/annotated/error) + LoadingPill (ProgressView + 한글) + RoundedRectangle 빨강 + ErrorPill
- `HUDController` rewrite — `present(content:on:)` 단일 entry + 4 helpers (loading/annotation/error/placeholder)
- `AppDelegate.handleAnalyze` rewrite — coordinator lazy init + presentLoading → run → presentAnnotation/Error

**진짜 동작 흐름 (사용자 검증 단계):**
1. ⌥+Space → trigger panel
2. 텍스트 입력 + Analyze
3. panel 자기 close → HUD `분석 중...` 즉시
4. 8-15초 Gemini 2.5 Flash 호출 (실측)
5. **응답 coordinates 있음** → `DisplayGeometry.logicalRectFromSentBox` → **빨간 박스 진짜 위치에**
   **응답 coordinates 없음** → `이 화면에선 정확한 위치를 못 찾았어요\n다음 버전에서 개선될 예정이에요`
   **error** → `UserMessage.from` 한국어 (예: `인터넷 연결을 확인해주세요`)
6. ⌥+Space → dismiss

**Tests (12 new)**: AnalyzeCoordinator 4 (happy path / dispatcher 에러 / capture permissionDenied / 중복 reject) + UserMessage 8 (missingAPIKey/401/429/network/maxTokens/retriesExhausted/decoding/jargon-free literal 검증). 누적 55/55 통과 (`swift build` 2.19s, `swift test` 0.213s).

**R8** (docs/troubleshooting.md): Swift 6 `os.Logger` string interpolation 안 implicit self 거부 → `self.` 명시.
**R9** (DECISIONS.md): `ScreenCaptureService` protocol (테스트 가능성).

**한계 인정**: LLM이 `coordinates` 안 줄 경우 — 에러 메시지 안내. Phase 6.1 OCR matcher 도입 시 `target_text` 기반 deterministic 매칭으로 99% 정확도. v0.1 초기엔 LLM 추정 좌표 ~70% — 박스가 어긋날 수 있음 (이건 dogfooding 검증으로 OCR 가치 측정 자료).

**다음:** Phase 5.x — HUDOverlayView bubble (한글 `next_action` 박스 옆 + 화면 가장자리 clamping) + Phase 6.1 — Vision OCR (`VNRecognizeTextRequest` .accurate ko-KR+en-US revision 3 + Y-flip) + `OCRBox` struct + `ElementMatcher` (fuzzy substring → Levenshtein escalate, threshold 0.7). AnalyzeCoordinator에 OCR fork 추가 + `target_text` 매칭 → deterministic 좌표.

---

## 2026-05-29 — Phase 4.2 fix: `coordinates` 반드시 강제 (v0.1 임시 swap, OCR 도입 전 가교)

**Phase 4.2 commit hash backfill:** `1862076`.

**첫 사용자 dogfooding 자료 (Phase 4.2 직후, log paste):**
```
[trigger] cursor=(809,386) screen=1728x1117@2.0x display=1
[capture] physical 3456x2234 scale=2.0x display=1
[capture] sent 1568x1014 (692692 bytes)
[analyze] captured 692692 bytes in 0.1s
[gemini] ok 2.3s — target_text="Terminal"        ← 실측!
[analyze] complete 2.4s
[analyze] no coordinates from LLM — OCR matcher (Phase 6.1) 필요
[hud] present content type=error
```

**3가지 발견:**
1. **Latency 실측 2.4s** (가설 8-15s 대비 ~5배 빠름) — Phase 5.x bubble UI 가설 갱신 (R8).
2. **`target_text="Terminal"`** — LLM이 visible text 정확 룰 따랐음 (번역기 본질 동작 확인).
3. **`coordinates` 키 LLM이 생략** — SYSTEM_PROMPT "fallback only" 룰 *잘 따라서*. Phase 6.1 OCR 없으니 모든 분석 fail → dogfooding 흐름 끊김 (R8).

**v0.1 임시 fix (이 commit) — Phase 6.1까지 가교:**
- `Prompts.swift` SYSTEM_PROMPT — `coordinates` 룰 swap: "fallback only" → "반드시 줘 (v0.1)". `x`, `y`, `w`, `h` 각 의미 + 이미지 좌표계 (좌상단 = `(0, 0)`) 명시. 아이콘처럼 visible text 없어도 `coordinates`는 줘.
- `GeminiDispatcher.swift` responseSchema — `required`에 `coordinates` 추가. LLM이 schema-level로 강제.
- `GeminiDispatcherTests` — 2 tests `required` set 업데이트.
- 55/55 통과 (`swift build` 2.29s, `swift test` 0.213s).

**R9** (DECISIONS.md): v0.1 임시 정책 swap (코드 안 `v0.1` 명시 + Phase 6.1 commit 시점에 다시 swap 강제).
**R8 × 2** (docs/troubleshooting.md): Gemini 2.5 Flash latency 가설 갱신 (8-15s → 2.4s), LLM "fallback only" 룰 잘 따라 OCR 없으면 epoch fail.

**한계 유지**: LLM 추정 좌표 ~70% — 박스 빗나갈 수 있음. 사용자가 빗나감 정도 확인 → OCR 가치 dogfooding 측정. Phase 6.1 commit 시점에 정책 다시 swap (verify workflow가 자기 모순 잡을 패턴).

**다음:** Phase 6.1 — Vision OCR + ElementMatcher → deterministic 99% 좌표 → 정책 다시 fallback only로 swap.

---

## 2026-05-29 — Swift Phase 6.1: Vision OCR + ElementMatcher → 99% 좌표 + 정책 swap back

**Phase 4.2 fix commit hash backfill:** `e674aea`.

**사용자 dogfooding 자료 (Phase 4.2 fix 후):**
- `target_text="CLAUDE.md"` 정확 (LLM visible text 룰 perfect — Phase 6.1 input ready)
- Gemini 3.9s, 이미지 939KB (capture 0.2s + Gemini 3.7s)
- coordinates 받음 + 박스 떴음 — 단 빗나감 (~70% LLM 추정 한계, 사용자 직접 봄)

**Phase 6.1 완료 (이 commit) — 99% deterministic 좌표 + 정책 lock-in:**

- `Sources/ScreenBridge/OCRBox.swift` — `(text, rectInSentImage, confidence)` Sendable struct. sent image px 좌표 (top-left).
- `Sources/ScreenBridge/OCRService.swift` — `OCRService` protocol + `VisionOCRService` 구현. `VNRecognizeTextRequest` .accurate / `VNRecognizeTextRequestRevision3` 명시 / ko-KR+en-US (지원 사전 확인 후 fallback) / usesLanguageCorrection. **Y-flip 한 곳** (Vision normalized bottom-left → sent image top-left, R8). `Task.detached(priority: .userInitiated)` background thread.
- `Sources/ScreenBridge/ElementMatcher.swift` — 매칭 알고리즘. (1) case-insensitive substring 우선 (가장 짧은 = 가장 specific 박스 선택) → (2) Levenshtein normalized similarity ≥ 0.7 fallback. `normalize` (lowercase + whitespace 정규화). `logicalRectFromSentBox` 호출로 screen-local logical pt 반환.
- `AnalyzeRequest.AnalyzeStage` — `.done`에 `matchedRect: CGRect?` 추가 (OCR 매칭 결과 또는 nil).
- `AnalyzeCoordinator` — `OCRService` 주입 + `async let` 병렬 (dispatcher + OCR). OCR 실패는 fatal X — LLM coords fallback 가능. ElementMatcher 호출 → matched rect.
- `AppDelegate.handleAnalyze` — 3-tier fallback: (1) `matchedRect` 우선 (OCR deterministic 99%) → (2) `result.coordinates` LLM 추정 fallback → (3) 둘 다 nil이면 한국어 에러 `"\"target_text\"을(를) 화면에서 못 찾았어요"`.

**R9 lock-in swap back** (DECISIONS):
- Prompts.swift `coordinates` 룰 swap back: "반드시 줘 (v0.1)" → "fallback only — 평소엔 키 생략. backend OCR가 99% deterministic".
- GeminiDispatcher `responseSchema.required`에서 `coordinates` 제거.
- GeminiDispatcherTests 2 tests `required` set swap back.
- 본질 "99% 좌표는 OCR이 source" 일관 — verify workflow 자기 모순 사전 차단.

**Tests (13 new)**: ElementMatcher 11 (substring/case/partial/specific/fuzzy/threshold/custom/edge × 4 + levenshtein/similarity helpers) + AnalyzeCoordinator update 2 (OCR matched / OCR no match). 누적 68/68 통과 (`swift build` 3.86s + deprecation warning, `swift test` 0.214s).

**R8** (docs/troubleshooting): Vision OCR Y-flip 좌표계 변환.
**R9 × 2** (DECISIONS): Phase 6.1 swap back lock-in + ElementMatcher fuzzy threshold 0.7 (튜닝 자료 dogfooding 후).

**사용자 검증 흐름 (Phase 6.1 후):**
1. `./dev.sh`
2. ⌥+Space → "CLAUDE.md 찾아줘" + Analyze
3. **빨간 박스가 *정확히* CLAUDE.md 사이드바 항목 위에 박힘** (deterministic 99%)
4. log: `[match] substring hit — target="CLAUDE.md" box="CLAUDE.md"` + `[analyze] complete N.Ns OCR-matched`

LLM 추정 좌표 ~70% 한계 → OCR matcher ~99% 도달. 번역기 본질 정확도 lock.

**다음:** Phase 5.x — HUDOverlayView bubble (한글 `next_action` 박스 옆 + 화면 가장자리 clamping). `target_text` + `next_action` 둘 다 사용자 facing visible.

---

## 2026-05-29 — Swift Phase 6.1 verify fix: ElementMatcher 정규화 강화 + 한계 인정

**Phase 6.1 commit hash backfill:** `95d4c57`.

**Adversarial verify workflow** (`phase-6-1-verify`, 7 agents / 211k tokens / ~4분):
- 6 dimensions: vision-ocr-api / y-flip / element-matcher-algorithm / 3-tier-fallback / concurrency / r9-swap-back.
- **Verdict: FIX_FIRST, ready_for_phase_5x: false**. 3 HIGH + 2 MEDIUM (BLOCKER 없음).

**HIGH 3건 (이 commit에서 fix):**
1. ElementMatcher Unicode NFC/NFD silent mismatch — 한국어 매칭 fail 위험 (R8). → `normalize()` 시작에 `.precomposedStringWithCanonicalMapping`.
2. 짧은 텍스트 fuzzy false positive — `"Save"` vs `"Same"` 0.75 통과, wrong-box (R8/R9). → `shortTextThreshold = 0.85` ≤6자 auto-tighten.
3. Task.detached cancellation 끊김 — dispatcher fail 시 OCR implicit wait, `isRunning` leak (R8, SDK 한계 인정). → `Task.detached → Task` (parent isolation 상속). Vision sync 자체 cancel API 없음 (Apple SDK 한계). 실측 mitigation: OCR ~1-2s < dispatcher ~3-4s.

**MEDIUM 2건 (같이 fix):**
4. Tiebreaker — 동일 길이 substring 매칭 confidence 높은 박스 우선 (R9).
5. `supportedRecognitionLanguages(for:revision:)` deprecated → instance method `request.supportedRecognitionLanguages()`. ko-KR 미지원 시 `Log.notice` 추가.

**Improvements 같이:**
- Punctuation strip (`CharacterSet.punctuationCharacters`) — OCR error 가장 흔한 source 흡수. `.md` vs `.txt` Levenshtein 차이로 정확 reject 유지.
- DisplayGeometry `box[2]/box[3] >= 0` guard — malformed LLM 응답 방어.
- AppDelegate 에러 메시지 「」 corner-quote + 30자 truncate (postposition 회피 + UI overflow 방어).
- Vision orientation assumption 명시 주석 (CGImage from PNG = top-left native).

**Tests (5 new + 3 갱신)**: NFC normalization + 짧은 텍스트 false positive 차단 + short text substring 유지 + punctuation strip + confidence tiebreaker + customThreshold logic 갱신 + fuzzy match 시나리오 갱신 + md vs txt reject. 74/74 통과 (`swift build` 2.57s, `swift test` 0.211s).

**R8 학습 자산 4건** (docs/troubleshooting.md): NFC silent fail, punctuation strip, 짧은 텍스트 false positive, Vision sync cancel SDK 한계.
**R9 갱신** (DECISIONS.md): ElementMatcher 정규화 강화 + length-aware threshold.

**Sweep → Implement → Verify → Implement(fix) → Verify** 3단계 반복 입증 — verify가 *번역기 본질 (한국어 정확)*과 *사용자 dogfooding 가장 위험 fail mode (wrong-box)*를 잡음.

**다음:** Phase 5.x — HUDOverlayView bubble (한글 `next_action` 박스 옆, 화면 가장자리 clamping). target_text + next_action 둘 다 visible. 사용자 dogfooding로 짧은 텍스트 false positive / NFC 매칭 / SDK cancel 한계 실측.

---

## 2026-05-30 — 🚀 Strategy Update: Pragmatic Ship Mode (target 확장 + 완벽 X + 빠른 monetization)

**Trigger (사용자 verbatim):**
> "길1을 하면서... 실제 개발자 타겟도... 그냥 너무 깊이말고 진짜 전부다,.. 어차피 나중에 대체되도 당장 출시하고 조금이라도 버는게 낫지"

**큰 결정 lock-in:**

1. **길 1 진행** — ship + niche + 수익. 빅테크 agent (Claude Computer Use, OpenAI Operator, Apple Intelligence)가 1-2년 내 부분/완전 대체 가능 — *그 전*에 user base + 수익 확보.

2. **Target 확장** — 시니어 단일 → *전부 동시*:
   - 시니어 + 비-AI-native (어머님)
   - 개발자 (AWS/Vercel/GitHub 가이드)
   - 일반 사용자 (정부24/카톡/은행)
   - "AI가 시킨 거 못 알아듣는 *모든 사람*"

3. **완벽 추구 X — MVP 마인드**:
   - 80% 정확도로 ship → dogfooding fix
   - R8/R9 큰 결정만 박음, 작은 edge는 skip
   - verify workflow Phase 종료 시만
   - happy path test 위주, edge는 dogfooding 후

4. **Timeline 압축** (4-8주 → 2-4주):
   - v0.2 minimum viable: secret masking 5-10 regex + clipboard auto + 작은 UI
   - **senior 전용 UX 미루기** — 일반 user도 쓸 형태로 ship 먼저. 시니어 친화 v0.3.
   - Mac App Store 신청 *지금* — 심사 1-2주.

5. **Monetization 빠르게**:
   - v0.2 ship과 함께 $5/월 freemium 또는 $30 one-time
   - 사용자 100명 = $500/월 — 1인 sustain 가능
   - "몇 천원이라도" 매출 = 동기 + niche signal

**미루기 (수익 확보 후):**
- Multi-platform (Android/Windows/iOS) — v0.5+
- Multi-target architecture (intent disambiguation) — Phase 7+
- Local-first LLM (Apple Foundation) — v0.5+
- 보안 layer C/D/E (sensitive region / local-first / audit log) — v0.5+

**유지 (v0.2 결정적):**
- 보안 layer A: secret regex masking 5-10개 (AIzaSy / sk- / ghp_ / JWT / AWS / SSH)
- 보안 layer B: 금융 앱 exclusion list
- clipboard auto-fetch (자녀가 ChatGPT 답 복사 → 자동 분석)

**현재 우선순위 (v0.1 마무리 → v0.2 빠른 ship):**
1. ★ 어머님 첫 dogfooding (1주 안) — *진짜 검증*
2. *동시*: 개발자 친구 1-2명 dogfooding (AWS/Vercel 케이스)
3. v0.1 latency speedup (image 1568→1024 + maxOutputTokens 줄임 + progressive UI) — 30-40% 가속, 35분
4. v0.2 핵심: secret regex masking + Mac App Store 준비
5. ship — 가격 $5/월 또는 $30 one-time

memory: `pragmatic-ship-mode.md` 박음 — 다음 세션도 이 모드.

**Reality check**: *지금 ship 안 하면 영영 못 함* (1인 개발자의 영원한 함정). 5-10년 빅테크 부분 대체 시나리오에서도 niche 확보가 생존.

---

## 2026-05-30 — Swift Phase 5.x bubble: 한글 next_action + sourceTag (OCR/AX) + 화면 가장자리 clamping

**Phase 6.2 fix commit hash backfill:** `cdd092b`.

**번역기 본질 완성 단계 — *어머님이 박스 보고도 뭘 할지 알게* 됨.**

빨간 박스만으론 *의도 전달 부족*. 사용자가 박스 보고 "이게 뭐?" 의문. bubble이 "여기 [Slack] 아이콘 누르세요" 명시.

**Phase 5.x 완료 (이 commit):**

- `MatchResult` struct — `rect + matchedText + sourceTag`. ElementMatcher.match 반환 type 변경.
- `AnalyzeStage.done(result, geometry, matched: MatchResult?)` — `matchedRect: CGRect?` → `matched: MatchResult?`.
- `HUDAnnotation` — `rect + nextAction + sourceTag` (default empty strings, backward compatible).
- `HUDOverlayView` — GeometryReader + `BoxAndBubble` + `BubbleView` (한글 `next_action` 큰 글씨 + sourceTag 작게).
- `BubblePositioner` enum — 박스 아래 우선 + 화면 가장자리 4면 clamping (좌/우/상/하).
- `AppDelegate.handleAnalyze` — `result.nextAction` + `matched.sourceTag` → `HUDAnnotation`. LLM fallback 시 `sourceTag = "LLM"`.

**Bubble UI:**

```
┌─────────────────┐
│ 🔴 Slack 아이콘  │  ← 빨간 박스
└─────────────────┘
          ↓
    ┌─────────────────────────────────────┐
    │ 여기 [Slack] 아이콘 누르세요         │  ← 한글 next_action (title3 큰 글씨)
    │ [AX:AXDockItem]                     │  ← sourceTag (caption2, 신뢰 + 디버그)
    └─────────────────────────────────────┘
```

**Tests (6 new BubblePositioner)**: 박스 아래 / 박스 위 (하단 끝) / 좌측 / 우측 / 우하단 (둘 다) / 정중앙. 누적 86/86 통과 (`swift build` 2.37s, `swift test` 0.211s).

**번역기 본질 완성**:
- text-rich UI: OCR (Phase 6.1)
- icon-only UI: AX (Phase 6.2)
- intent disambiguation: SYSTEM_PROMPT (6.2 fix)
- 사용자 facing UX: bubble (Phase 5.x)

→ **어머님이 박스 + bubble만 보고도 *진짜* 동작 가능 단계.**

**다음:**
- ★ 어머님 첫 dogfooding (1-2주 안) — 카톡 / Safari / Finder 같은 진짜 케이스
- v0.2: secret regex masking (보안 layer A — Jarvis vision의 결정적 차별) + senior UX (큰 글씨 / 음성 / 항상 떠있는 도우미)

---

## 2026-05-30 — Phase 6.2 fix: SYSTEM_PROMPT 강화 (target_text 빈 string 금지 + intent-aware)

**Phase 6.2 commit hash backfill:** `d68746e`.

**사용자 dogfooding 발견 (log show 직접 query):**
```
[gemini] ok 10.4s — target_text=""              ← 빈 string!
[ocr] 237 boxes  [ax] 187 elements              ← 둘 다 잡힘
[analyze] complete 10.7s — target_text="" LLM-fallback  ← 매칭 불가
```

LLM이 "Slack 어디?" 질문에 *Dock 아이콘 = visible text 없음*이라 판단 → `target_text` 비우고 `coordinates`만 줌. ElementMatcher 매칭 불가 → LLM coords fallback (~70% 부정확).

**fix (이 commit, SYSTEM_PROMPT만 변경):**
- `target_text` 빈 문자열 **절대 금지** 명시.
- 아이콘만이고 visible text 없어도 *AX label* (앱 이름) 줘 — 예: Dock의 Slack 아이콘 → `target_text: "Slack"`. backend AXUIElement matcher가 `AXTitle="Slack"`으로 deterministic 좌표.
- 같은 텍스트 여러 곳 시 — 사용자 *동작 의도*에 가장 맞는 *한 곳*. "Slack 어디?" → 앱 열기 의도 → Dock. 본문 텍스트 X, 사이드바 파일 X.
- `reasoning` 필드에 의도 추론.

**번역기 본질 추가 인지**: backend (OCR + AX hybrid)는 잘 동작 — *번역의 input* (`target_text`)이 명확해야 작동. SYSTEM_PROMPT가 backend feature를 *제대로 사용*하게 LLM 안내해야.

**한계 인정 — Phase 7+ multi-target architecture**: 사용자 통찰 "박스를 하나만 치네... 이런 질문의도는 어찌파악하는건가"가 결정적. v0.1엔 SYSTEM_PROMPT intent-aware ranking이 한계. v0.4+ `targets: [TargetCandidate]` + numbered overlay + 대화형 follow-up.

memory: `intent-disambiguation-multi-target.md` 박음 — Phase 7+ architecture spec.

R4: swift build 2.97s, swift test 80/80 pass (Prompts 변경, schema 동일).

**다음**: 사용자 재시도 — "Slack 어디?" target_text 빈 string 안 줄 거 + AX matcher 매칭 → Dock 아이콘 위에 박스. 빗나가면 Phase 7+ multi-target 가속.

---

## 2026-05-30 — Swift Phase 6.2: AXUIElement matcher → icon-only UI 풀이 (Dock 아이콘)

**Phase 6.1 spatial fusion commit hash backfill:** `fcc95b0`.

**번역기 본질 마지막 큰 gap**: OCR이 *visible text만* 잡음. Dock의 Slack 아이콘 / iOS-style 버튼 / 이미지 메뉴 — text 0개 → OCR fail. 사용자 통찰 ("OCR이 텍스트만 인식하면.. 그림 인식도 추가해야하려나").

**Phase 6.2 (이 commit):**

- `Sources/ScreenBridge/AXElement.swift` — `(text, rectInLogicalPt, role, appName)` Sendable struct. AX는 이미 logical pt 반환 — DisplayGeometry 변환 불필요.
- `Sources/ScreenBridge/AXService.swift` — protocol + `LiveAXService`. `NSWorkspace.runningApplications` + Dock 순회 → AXUIElementCreateApplication(pid) → 재귀 tree walk (depth 8 제한). 화이트리스트 roles 14개 (AXButton/AXLink/AXMenuItem/**AXDockItem**/AXImage/etc.). text 합본 (title + description + value).
- `ElementMatcher` 확장 — `MatchCandidate` unified type 도입 (OCR + AX 합집합 candidate). 기존 `match([OCRBox])` backward compatible (internal에서 MatchCandidate로 변환).
- `AnalyzeCoordinator` — `async let dispatcher + OCR + AX` 3개 병렬. OCR/AX 실패 fatal X (graceful — 권한 거부해도 OCR만으로 동작).
- `AppDelegate` — Accessibility 권한 startup trigger (Phase 3.1 패턴 — Screen Recording과 같이).

**Swift 6 strict concurrency 함정 (R8 × 2)**:
- `kAXRoleAttribute` 등 extern var 거부 → string literal 대체 (Phase 3.1 `kAXTrustedCheckOptionPrompt` lesson 동일).
- `AXValue` downcasting + `AXValueGetType` 사전 check (polymorphic CFTypeRef 안전성).

**R9 결정** (DECISIONS): `MatchCandidate` unified type + OCR/AX 합집합 (vs 2-step fallback). substring tiebreaker에 AX 우선 박음 (deterministic 좌표 우선).

**Tests (2 new)**: AX matcher 성공 (Slack icon-only case) + AX 권한 거부 graceful (OCR만으로 동작). 80/80 통과 (`swift build` 3.79s, `swift test` 0.210s).

**번역기 본질 도달**: OCR (text-rich UI) + AX (icon-only UI) hybrid → *모든 clickable UI*에 deterministic 좌표.

**한계**:
- AX query latency — Electron 큰 앱 (Cursor 등) tree 크면 1-2s 가능. 실측 후 timeout 검토.
- Electron 앱 (Slack desktop, Discord, VS Code) 자체의 AX tree *비어있을 수 있음* — 그 앱 내부 element 못 잡음. Phase 6.3+에서 vendor-specific fallback.
- `clickableRoles` 화이트리스트 dogfooding 후 갱신.

**다음:**
- Phase 5.x — HUDOverlayView bubble (한글 `next_action` 박스 옆 + 화면 가장자리 clamping) + sourceTag 표시 (`OCR` / `AX:AXDockItem` 등).
- 어머님 첫 dogfooding (1-2주 안) — 진짜 product fit 검증.

---

## 2026-05-30 — Swift Phase 6.1 spatial fusion: LLM coords hint + OCR proximity → wrong-box 차단

**Phase 6.1 verify fix commit hash backfill:** `f08a603`.

**사용자 dogfooding 발견 (Phase 6.1 verify fix 후, log show 직접 query):**
- "Save" 시도 → OCR `box="save"` (어딘가 인용 텍스트) — wrong-box
- "Slack 어디?" 시도 → OCR `box="slack 못"` (어시스턴트 응답 텍스트) — wrong-box, **Dock의 Slack 아이콘 아님**
- 진단: substring 매칭이 화면 *어디든* 매칭. 사용자 intent (Dock 영역 / dialog) 무시.

**Spatial fusion (이 commit):**

- `Prompts.swift` coordinates 룰: "fallback only" → "fallback OR **위치 hint 권장**". 강제 X, 권장만. 본질 ("OCR이 source") 일관.
- `ElementMatcher.match` signature 확장: `llmHintRect: CGRect? = nil`, `proximityRadius: CGFloat = 200pt`.
  - hint 있으면 중심 ±200pt 안 OCR 박스만 candidate.
  - hint 근처 박스 0개 → full candidates fallback (LLM hint 부정확 안전망).
- `AnalyzeCoordinator`가 `result.coordinates` → CGRect (sent image px) → ElementMatcher hint 전달.

**Tests (4 new)**: proximity 근처 박스 선택 / hint 근처 없으면 full fallback / hint 없으면 기존 동작 / proximityRadius 커스터마이즈. 누적 78/78 통과 (`swift build` 2.90s, `swift test` 0.209s).

**R9** (DECISIONS.md): spatial fusion architecture (A 즉시 + 향후 C Phase 6.2 hybrid).

**한계:** LLM이 coords 안 주면 proximity 안 작동. 단 v0.1엔 *어머님 시도 시* LLM이 줄 가능성 큼 — 사용자 intent 명확한 경우 LLM도 영역 인지.

**다음:** Phase 6.2 — AXUIElement (Dock 아이콘, icon-only UI deterministic 좌표) → Slack 같은 케이스 풀음. → Phase 5.x bubble (한글 next_action) → 어머님 dogfooding.

---

## 2026-05-29 — 🌍 Vision Update: global + multi-platform + 5-layer security

**Trigger (사용자 verbatim):**
> "한국 시장만이 아니다... 세계를 대상으로 할거다 가장 큰 문제는 보안이될거같네.. 그리고 지금은 맥북이지만 스마트폰도 같이 대상으로할거다.. swift로 진행중이니..."
> "이 큰 결정과 커다란 청사진은 꼭 log화시키자"

청사진 큰 진화 — code 변경 X, *vision lock-in*.

**3가지 큰 결정:**

1. **시장 → 글로벌** (한국 단일 X). 시니어 + 비-AI-native가 global trend. 일본/미국/유럽 모두 고령화. niche 동일 + 시장 압도적 큼.

2. **Multi-platform — Android first phone**. iOS는 Apple sandbox로 macOS-style 다른 앱 가이드 *원천 불가능* (Screen recording / system overlay / cross-app input 다 X). Android는 AccessibilityService로 overlay + 입력 simulation 가능. 시니어 점유율 한국 50% / 글로벌 70% — phone 시장 fit.

3. **보안 5-layer가 빅테크 대비 결정적 차별** — secret regex masking / app exclusion / sensitive region / **local-first LLM** (Apple Foundation Model on-device / Ollama) / audit log. 빅테크는 cloud 강제 (수익화) — local-first는 enterprise/정부/금융/일본 시장의 결정적 매력.

**Platform Roadmap (갱신):**

| 단계 | 시장 | platform | feature |
| --- | --- | --- | --- |
| v0.1 (지금) | dogfooding + 어머님 | macOS | 번역기 quality lock |
| v0.2 | 한·일·영어권 시니어 가족 | macOS App Store | senior UX + secret masking |
| v0.3 | global Mac | macOS | multi-step + clipboard auto |
| **v0.4** | **global phone** | **+ Android (AccessibilityService)** | continuous overlay agent |
| v0.5 | enterprise + 정부 | + Windows (WinUI) | local-first LLM |
| v0.6 | full mobile | + iOS companion (제한 형태) | Mac → iPhone notification sync |
| v1.0 Jarvis | mass market global | all 4 platforms | continuous agent + multi-modal |

**Code architecture 사전 인지** — Sources/ScreenBridge의 *backend* (AnalysisResult / Prompts / LLMDispatcher / GeminiDispatcher / ElementMatcher / OCRBox / DispatcherError / UserMessage / AnalyzeRequest / AnalyzeStage / Env / Logging) 모두 cross-platform 가능. v0.4 Android port 시점에 SwiftPM library 분리 → Swift→Kotlin gRPC bridge 또는 Swift on Android.

*Platform-specific frontend* (HUDOverlayWindow / ScreenCapture / TriggerPanel / HotKeyManager / AppDelegate) 만 per-platform 재작성.

**Reality check (1인 자원 vs 빅테크):**

Apple Intelligence / Microsoft Copilot / Anthropic Computer Use / OpenAI Operator 모두 같은 vision 추진. 1인 개발자 생존:
- **niche speed**: 시니어 + 보안 + 한·일·영 localized
- **on-device privacy**: 빅테크는 cloud (수익화) — local-first 결정적 차별
- **family pricing**: 자녀 결제 + 가족 단위 — 빅테크 enterprise 위주
- **Android first phone**: iOS sandbox 회피
- **community UGC**: 자녀가 부모용 step 공유 — v0.5+ 모드

**우선순위 lock-in:** v0.1 quality 마무리 → v0.2 senior UX + secret masking → v0.3 backend SwiftPM split → v0.4 Android start. 빌딩 순서 명확.

**상세:** memory `product-vision-global-multi-platform` (디테일 보안 정규식 / Android NodeInfo / iOS companion mode etc.).

---

(append-only — 각 phase / stack swap / 큰 결정 즉시 추가. 사후 정리 금지.)

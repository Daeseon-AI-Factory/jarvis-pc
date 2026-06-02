# Current State — 다음 세션 HANDOFF

> ⚠️ **새 세션 읽는 순서**: 이 STATE.md → PRODUCT.md (본질) → DECISIONS.md (확정 결정) → SCRATCHPAD.md (미해결). **SPEC.md는 Tauri 기준 stale — 따라가지 말 것** (아래 "stack" 참조).

## Stack: Swift macOS native (확정, 2026-05-27 swap)

- SwiftPM + SwiftUI + AppKit, macOS 14+, Swift 6 language mode.
- **Tauri v0.1 attempt는 폐기** → `tauri-archive` branch + `v0.1-tauri-attempt` tag로 보존. main에는 Tauri 코드 없음.
- swap 근거: `DECISIONS.md` "STACK SWAP" + `PROJECT_TIMELINE.md`. 요약 — macOS HUD는 Apple SDK 표준 use case인데 Tauri는 cross-platform framework라 16 layer를 trial-and-error로 재발견했음. Swift는 SDK 한 줄.
- 빌드: `swift build` / 실행: `swift run` (cargo-style).

## 완료

- [x] Swift Phase 0.1 — SwiftPM scaffold (`571e213`)
- [x] Swift Phase 0.2 — menu-bar shell (`63c0568`): `.accessory` dock 숨김 + NSStatusItem 트레이 (eyeglasses, Trigger/Open sessions/Quit) + Carbon `RegisterEventHotKey` ⌥+Space + NSPanel trigger panel (cursor monitor 중앙). `swift build` 2.26s.
- [x] Swift Phase 2.1 — AnalysisResult Codable struct (`e075f0f`): snake_case CodingKeys 명시 (R9), `coordinates: [Int]?` optional (OCR fallback only — 번역기 본질 "99% 좌표는 OCR source"), `raw`는 Codable 분리 + `withRaw(_:)` builder (R9, `responseSchema` 1:1 보존). 6 tests 통과.
- [x] Swift Phase 2.2 — Prompts.swift + Env.swift (`f7b799b`): SYSTEM_PROMPT 4개 본질 (target_text 정확/친화 톤/한 화면 한 동작/coordinates fallback) ✗/✓ 페어 직역 (R9). `.env` parser dep 0 직접 (R9). 18 tests 통과.
- [x] Swift Phase 2.3 — GeminiDispatcher + os.Logger swap (`8a60c2f`): URLSession async + `responseMimeType`+`responseSchema` 강제 + image FIRST + retry 429/5xx exp backoff + timeout 30/60s. `JSONSchema` indirect enum (R8). NSLog → `os.Logger` 전체 swap (R9, 사용자 좌절 해결, `log stream` 한 명령). HotKeyManager OSStatus 명시 (R8). 24 tests.
- [x] Swift Phase 3.1 — ScreenCaptureKit + Permissions + LastTriggerContext + DisplayGeometry (`7f4d4f4`): SCShareableContent + SCScreenshotManager + 1568 다운스케일 + 4-layer 좌표 캡슐화 + 권한 startup eager + `dev.sh` codesign. 29 tests.
- [x] Swift Phase 3.1 verify fix (`131da7b`): adversarial verify workflow 4 BLOCKER + 3 HIGH. SCContentFilter Apple shape, NSScreen.main 자기 모순 fix, `globalAppKitRect` helper, Permission denial 1.5s 재확인, LastTriggerContext fresh fetch, codesign `--identifier`. 33 tests.
- [x] Swift Phase 5.0 — HUDOverlayWindow 빈 골격 (`a51dc09`): NSPanel 5 본질 (Layer 1/4/7/8/9) + presentPlaceholderCenter. **첫 *눈으로 보는* 단계** — 사용자 직접 검증: 빨간 박스 떠봄 + ⌥Space dismiss OK.
- [x] Swift Phase 4.2 — AnalyzeCoordinator + UserMessage + HUDContent (`1862076`): 진짜 동작 시작. ScreenCaptureService protocol + AnalyzeCoordinator actor + UserMessage 한국어 매핑 + HUDContent 3 case. 12 new tests.
- [x] Swift Phase 4.2 fix — `coordinates` 반드시 강제 (`e674aea`, v0.1 임시 swap): SYSTEM_PROMPT + schema required에 추가. Gemini latency 실측 2.4s, target_text 정확.
- [x] Swift Phase 6.1 — Vision OCR + ElementMatcher → 99% + R9 swap back (`95d4c57`): OCRBox + OCRService + ElementMatcher + AnalyzeCoordinator async let 병렬 + AppDelegate 3-tier fallback. 13 new tests.
- [x] Swift Phase 6.1 verify fix (`f08a603`): adversarial verify 3 HIGH + 2 MEDIUM. NFC normalize + short text 0.85 + Task + tiebreaker + punctuation strip.
- [x] Swift Phase 6.1 spatial fusion (`fcc95b0`): LLM coords hint + OCR proximity filter (radius 200pt) → wrong-box 차단. SYSTEM_PROMPT hint 권장 (강제 X).
- [x] Swift Phase 6.2 — AXUIElement matcher (`d68746e`): icon-only UI 풀이. OCR + AX hybrid + MatchCandidate unified type.
- [x] Swift Phase 6.2 fix — SYSTEM_PROMPT 강화 (`cdd092b`): target_text 빈 string 금지 + intent-aware ranking. 사용자 검증 OK (Slack 아이콘 정확).
- [x] Swift Phase 5.x bubble (이 commit, **번역기 본질 완성 — 어머님 dogfooding 가능 단계**): MatchResult struct (rect + matchedText + sourceTag) + AnalyzeStage.done matched: MatchResult?. HUDAnnotation 확장 (nextAction + sourceTag). HUDOverlayView GeometryReader + BoxAndBubble + BubbleView (한글 title3 + sourceTag caption2). BubblePositioner (박스 아래 우선 + 4면 가장자리 clamping). AppDelegate.handleAnalyze nextAction/sourceTag 전달. 6 new BubblePositioner tests. 86 tests 통과 (`swift build` 2.37s, `swift test` 0.211s). **번역기 본질 도달**: 박스 + 한글 안내 + source 신뢰 표시.
- [x] Swift Phase 5.x-late — multi-target overlay + LLM target_role hint + Gemini pre-warm (`43a44ff`, `f5a1261`, `c15578e`): top 2 distinct candidates + primary 빨강/alternative 회색 dashed + 번호 라벨. LLM schema-level `target_role` AX role 명시 (keyword fallback). TLS/DNS pre-warm으로 첫 호출 ~1-2s ↓. 86 tests.
- [x] Swift Phase 7.0 — Jarvis continuation scaffold (이 commit, **5-stage evolution 시작**): SessionState enum + CancelReason + sessionID/history fields + snapshotState/continueSession/cancelSession (transition 미-wire stub). AnalysisResult 3 새 필드 (taskComplete/requiresConfirmation/stepActionSummary, *default 값으로 v0.1 호환*). AnalyzeRequest 2 새 필드 (sessionID/previousSteps) + StepSummary struct. Prompts 2 새 clause (연속 작업 + 되돌릴 수 없는 동작). IrreversibleActions keyword filter (한국어 + 영어 30+ 단어). responseSchema에 3 새 필드. 12 new tests. **98 tests 통과**. *behavior change 없음* — Phase 7.1에서 hotkey 분기 + HUD in-place swap 박음.

**Last commit:** Phase 7.0 scaffold (hash 다음 commit에 갱신)
**검증 안 됨:** `swift run` 실제 smoke (menu bar 아이콘 + ⌥Space → panel). 사용자 manual 필요 — GUI라 agent가 직접 못 띄움.

## Next step (다음 세션 시작점)

**Phase 2.x — LLM dispatcher (Swift)** — 2026-05-29 sweep workflow advice 반영 (AnalysisResult 첫, dispatcher 다음, Phase 5.0 빈 골격 끼움, OCR forward declare):

1. ✅ Phase 2.1 — AnalysisResult struct (`e075f0f`).
2. ✅ Phase 2.2 — Prompts + Env (`f7b799b`). SYSTEM_PROMPT 4개 본질 ✗/✓ 페어 직역, `.env` parser dep 0.
3. ✅ Phase 2.3 — GeminiDispatcher + os.Logger swap (`8a60c2f`). URLSession + responseSchema + retry, JSONSchema indirect enum.
4. ✅ Phase 3.1 — ScreenCapture + Permissions + LastTriggerContext + DisplayGeometry (`7f4d4f4`).
4b. ✅ Phase 3.1 verify fix (`131da7b`) — BLOCKER 3 + HIGH 3 from adversarial workflow.
5. ✅ Phase 5.0 — HUDOverlayWindow 빈 골격 (`a51dc09`). 사용자 검증 통과.
6. ✅ Phase 4.2 — AnalyzeCoordinator + UserMessage + HUDContent (`1862076`). *진짜 동작*.
6b. ✅ Phase 4.2 fix — `coordinates` 반드시 강제 v0.1 임시 swap (`e674aea`).
7. ✅ Phase 6.1 — Vision OCR + ElementMatcher → 99% + R9 swap back (`95d4c57`).
7b. ✅ Phase 6.1 verify fix (`f08a603`) — NFC + short text + Task + tiebreaker + punctuation strip.
7c. ✅ Phase 6.1 spatial fusion (`fcc95b0`) — LLM coords hint + OCR proximity → wrong-box 차단.
7d. ✅ Phase 6.2 AXUIElement matcher (`d68746e`) — icon-only UI 풀이 (Slack/Dock).
7e. ✅ Phase 6.2 fix (`cdd092b`) — SYSTEM_PROMPT intent-aware. 사용자 검증 OK.
8. ✅ Phase 5.x bubble (이 commit) — 한글 next_action + sourceTag + clamping. **번역기 본질 완성.**
9. ★ **어머님 첫 dogfooding** (Phase 8.0 박은 후) + **개발자 친구 1-2명** (AWS/Vercel) *동시* — 진짜 검증.
10. ✅ **v0.1 latency speedup** — image 1024 + maxOutputTokens 줄임 + progressive UI + pre-warm 박힘 (commits `d57a890`, `c15578e`).
11. ✅ **v0.1.5 multi-target overlay + LLM target_role + pre-warm** — top 2 박스 + 번호 라벨. user-in-the-loop 차별 강화.
12. ✅ **Phase 7.0 scaffold** (`75a02ca`) — SessionState enum + AnalysisResult new fields (taskComplete/requiresConfirmation/stepActionSummary) + IrreversibleActions keyword filter. additive, behavior change X.
13. ✅ **Phase 7.1 continuation wire** (`2506d59`) — currentInstruction 저장 + continueSession + state transition + hotkey 분기 + 2-layer irreversible gate. 사용자가 매 step 재입력 X.
14. ✅ **Phase 7.2 dispatcher fallback** (`33fd37e`) — ClaudeDispatcher + FallbackDispatcher (Gemini 429 → Claude swap, JSONValue Sendable, tool_use forced JSON).
15. ✅ **Phase 7.2.1 hotkey throttle** (`dcb9164`) — 200ms (Probe C race guard).
16. ✅ **Phase 7.3 completion pill + audit log** (`a54b121`) — 초록 ✓ presentCompletion + SessionAuditLog JSON dump (`~/Library/Application Support/.../sessions/<uuid>.json`).
17. ✅ **v0.2 SecretMasker** (`2ffc163` — push protection amend) — 10 regex pattern (sk-/AKIA/ghp_/카드/주민번호). 5-layer 보안 Layer 1 박힘.

## 🔒 v0.2 local-first 로드맵 (2026-05-31 결정, Workflow `wiy4w4h3y`)

사용자 우려 정당 — cloud only는 Operator/Manus 자리 (차별 lose, senior/기업 못 씀). **3-tier hybrid** 박음.

### Phase 8.0 ⭐ — SensitivityRouter (오늘 다음 commit, 1-2h)
- `Sources/ScreenBridge/SensitivityRouter.swift` 신규
- `LLMRoutingDecision` enum: `.cloud / .localOnly / .blockedLocalModelNotInstalled`
- bundleID deny-list: 1Password / Bitwarden / KeychainAccess / 카카오뱅크 / 국민 / 신한 / 하나 / Toss / 신한카드 / BC / 삼성카드 / Mail compose
- AnalyzeCoordinator.run() 안 capture 후, dispatcher 호출 *전* Router 통과
- `.blockedLocalModelNotInstalled` → UserMessage "🔒 이 화면은 인터넷에 안 보내요. 다음 업데이트에서 보안 모드 추가됩니다."
- 5-layer 보안 Layer 2 박힘.

### Phase 8.1 — fixtures/sensitive_screens/ + Router 회귀 test (1주, ~3-4h)
- 1Password vault / 카카오뱅크 입금 / Mail compose / KakaoTalk DM 등 10장
- Router unit test 통과 (어떤 bundleID에서 어떤 decision 박는지)

### Phase 9.0 — Qwen2.5-VL-3B local dispatcher (1-3개월)
- `Package.swift` mlx-swift-lm dep 추가
- `Sources/ScreenBridge/QwenLocalDispatcher.swift` 신규 — LLMDispatcher protocol 구현
- First-launch model downloader UI (~2GB, 진행률, 백그라운드 재개)
- M1 RAM 감지 → 8GB load-on-demand (cold start 2-4s) / 16GB+ resident 옵션
- SettingsView "Privacy mode (off/auto/always-local)" 3-state toggle
- Probe D-prime (Week 1): 5 fixture sanity check, <70% 정확도면 즉시 cloud-only fallback

### Phase 9.5 — Apple FM swap (WWDC26 결과 dependent, ~6/8-12)
- 발표 시: `FoundationModelDispatcher.swift` 12-24h swap. 어머님 fit 완벽 (0GB shared, 2-4s).
- 발표 X: Qwen 유지, ship 진행. 다음 분기 재확인.

### Phase 10 — Mac App Store submission (v0.2 후)
- v0.2 cloud-only + Router 박힌 후 *먼저* submit (model download는 v0.3)
- reviewer note: deny-list + audit log + secret masking 명시

### v0.3-v0.4 (이후)
- **v0.3 W (plan-first)** — `plan: [PlanStep]?` schema, 1 LLM call 전체 plan, local OCR verify, checklist sidebar, TTS, Dock 도우미 icon, panic-X widget
- **v0.4 Y (screen-change auto opt-in)** — 능동 모드 toggle
- **v0.5 active monitoring** — hybrid edge+cloud, local 분류 + cloud trigger
- **Monetization** — $5/월 freemium + $30 one-time + BYOK (cloud 호스팅 비용 0)

⚡ memory `local-first-roadmap-5-layer-security` 박음 — 다음 세션 참조용.

⚡ memory `pragmatic-ship-mode` 박음 — 완벽 X, ship 우선, target *전부*.
4. Phase 3.1 — ScreenCaptureKit + Permissions (startup trigger 0.5단계 빨리) + LastTriggerContext (hotkey 콜백 즉시 cursor 저장, Layer 10 회피) + DisplayGeometry (4-layer 좌표 변환 캡슐화).
5. Phase 5.0 (sweep swap) — `HUDOverlayWindow.swift` 빈 골격, dispatcher 무관 검증 (`level=.screenSaver` / `ignoresMouseEvents=true` 영구 / collectionBehavior 셋 / multi-monitor frame pin).
6. Phase 4.2 — AnalyzeCoordinator (actor + async let 병렬, OCR forward declare stub) + TriggerPanel onSubmit 배선 + 한국어 에러 메시지 매핑 (network/timeout/permission/json → 비-AI-native 친화).
7. Phase 5.x — HUDOverlayView 빨간 박스 + bubble (한글 next_action, fallback "화면을 못 찾았어요").
8. Phase 6.1 — VisionOCR (`VNRecognizeTextRequest` .accurate ko-KR+en-US revision 3 + Y-flip) + OCRBox struct + ElementMatcher (fuzzy substring → Levenshtein escalate, threshold 0.7, fail 시 bubble만).

그 다음:
- **Phase 3.1** — ScreenCaptureKit (`SCShareableContent` + `SCScreenshotManager` 또는 `SCStream`). multi-monitor: cursor 있는 display (`NSEvent.mouseLocation` + `NSScreen`). DPR은 ScreenCaptureKit이 physical 반환 — `NSScreen.convertRect`로 logical. 다운스케일 1568.
- **Phase 4.2** — analyze flow: TriggerPanelView의 Analyze → capture + OCR(Vision) + dispatcher 병렬 → AnalysisResult.
- **Phase 5.x** — NSWindow HUD overlay: `.ignoresMouseEvents = true` (영구 click-through) + `.collectionBehavior=[.moveToActiveSpace]` + `.level = .screenSaver`(또는 .floating) + transparent. 빨간 박스 + bubble SwiftUI. 닫기 = ⌥Space 토글.
- **Phase 6.1** — OCR + element matching: Vision `VNRecognizeTextRequest` → (text, bbox) list. LLM `target_text` ↔ list fuzzy match → deterministic 좌표. (Tauri의 macocr subprocess + find_box 로직 그대로 포팅 — `DECISIONS.md` "99% 정확도 architecture").
- **Phase 6.2+** — sessions (FileManager `~/Library/Application Support/com.screenbridge.app/sessions/`), feedback, settings.

## 확정 결정 (DECISIONS.md 요약 — 다시 논의 불필요)

| 영역 | 확정 | 근거 |
| --- | --- | --- |
| Stack | Swift macOS native | macOS HUD = SDK 표준, Tauri 16 layer 회피 |
| Dispatcher | **Gemini 2.5 Flash + responseSchema 강제** | 무료 250 RPD, 8-15s, vision 좌표 안정. claude CLI 41s/Groq 76s 대비 |
| 좌표 | **LLM은 element 식별만, 좌표는 deterministic source** | vision LLM 픽셀 추정 ~70%. OCR(Vision)/AXUIElement ~99% |
| OCR | Vision framework `VNRecognizeTextRequest` 직접 (Tauri는 macocr subprocess였음) | native, 빠름, 의존성 0 |
| multi-monitor | cursor 있는 monitor 캡처 + **⌥Space 누른 시점 cursor 기록** | analyze 시점 cursor는 panel monitor로 옮긴 후 |
| HUD overlay | `.ignoresMouseEvents=true` 영구 (진짜 안경 click-through) | desktop 그대로 사용 + 위에 가이드 |
| JSON 강제 | Gemini=responseSchema, Anthropic=SYSTEM_PROMPT, Groq=json_object, OpenAI=response_format | vendor별 다름 |
| 이미지 | 1568×1568 cap 다운스케일 (Lanczos급) | vision tile 1 tile, 토큰/시간 절감 |

## 확정 SYSTEM_PROMPT 골자 (Prompts.swift에 그대로)

한국어. 핵심: (1) 화면에 실제 보이는 요소만, (2) 추상 지시 금지 ✗/✓ 예시, (3) **target_text 필수** = 클릭할 UI의 visible text 그대로 (backend가 OCR 매칭), (4) coordinates는 fallback, (5) JSON 외 텍스트 금지. 전문은 tauri-archive의 `src-tauri/src/prompts.rs` 또는 DECISIONS 참조.

## 학습 자산 (5 layer — 모두 stack 무관 transferable)

- `TROUBLESHOOTING.md` — 16+ entries (자세한 디버그 narrative, repo 내부)
- `DECISIONS.md` — 15+ entries (trade-off matrix)
- `PROJECT_TIMELINE.md` — append-only history
- `docs/troubleshooting.md` — terse publish ref (dual-write)
- `content/logs/jarvis-pc/*.mdx` — blog narrative (dual-write, 6 entries)
- `BUILD_REPORT.md` — v0.1 Tauri completion report

## 룰 (CLAUDE.md)

- R1-R7 회복력 (atomic commit, STATE 갱신, verify-before-commit 등). **R4의 `cargo check`/`tsc`는 Swift에선 `swift build` + `swift test`**.
- R8/R9 학습 자산 강제 (TROUBLESHOOTING/DECISIONS).
- dual-write (docs/troubleshooting.md + content/logs/) — non-trivial commit마다.
- `.git/hooks/pre-commit`이 코드 변경 + 학습 자산 동반 강제 (우회 `--no-verify`). **주의: `.git/`은 untracked라 새 머신 clone 시 hook 없음** (SCRATCHPAD 참조).

## SCRATCHPAD 미해결: 4 (SCRATCHPAD.md 참조)

---

## v0.3 5-layer 보안 완성 (2026-06-02 burst)

사용자 quote "전부다 해라 계속 될떄까지 가보자" → Workflow `w99oanivx` 박힌
v0.3 4주 plan을 Week 1+2+3 task 연쇄 박음.

### 5-layer 보안 5/5 박힘

| Layer | 박힘 | commit |
| --- | --- | --- |
| 1. SecretMasker (text mask) | ✓ 11 pattern (한국 PII 5개 박힘) | `2ffc163` + `11bbea1` |
| 2. SensitivityRouter (app exclusion) | ✓ 19 bundleID (한국 은행 7 + 카드 4) | `11bbea1` |
| 2.5. ContentMasker (OCR/AX redact) | ✓ candidate filter | `c936262` |
| 3. Region opt-out (image black box) | ✓ CGContext fill | `ae07cec` |
| 4. Local LLM (Qwen) | ✓ wire + publish + Settings toggle | `ef81ae6` + `5bbdf57` + `3f26a3f` |
| 5. Audit log (per-session JSON) | ✓ Phase 7.3 박힘 | `a54b121` |

### v0.3 박힌 commit 시간순 (2026-06-02)

```
26a1286  Phase 9.0 Week 1 (mlx-swift-examples dep + Qwen skeleton)
59cc0cb  Phase 9.0 Week 2-3 (Qwen wire + MLXVLM API drift fix)
ef81ae6  Phase 9.1 (Qwen 끼움 — SCREENBRIDGE_USE_LOCAL=1 toggle)
9f2f43a  Landing page (995 line HTML, Apple-style)
f35b930  MAX_TOKENS + scroll fix
11bbea1  Layer 2 SensitivityRouter + 한국 PII 5개 + Mac App Store SKIP
e4243ff  Session Inspector (별도 NSPanel + SwiftUI)
5bbdf57  진짜 publish wire (dispatcher name + privacy mode + Qwen tps)
c936262  Layer 2.5 ContentMasker
3f26a3f  SettingsView Privacy mode toggle
35962c9  Probe D-prime scaffold + 3 commits 통합 dual-write
ae07cec  Layer 3 Region opt-out
db05877  ModelDownloadProgress + ModelDownloadView (first-launch UX)
```

### Mac App Store SKIP → Notarized DMG path (Workflow 결정)

- AXUIElement sandbox 충돌 fatal (Rectangle/Hammerspoon/BetterTouchTool 동일)
- Apple Developer Program $99/년 등록 + codesign + notarytool submit + staple
- Sparkle 자동 update + EdDSA + GitHub Actions pipeline
- Ship target: **2026-06-27** Beta DMG
- v1.0 정식: **2026-09-30** (v0.4 Android first 박은 후)

### 사용자 시도 (현재 박힌 상태)

```bash
# Cloud mode (default):
./dev.sh
⌥+Space → "github 알림 끄기"

# Local mode (보안 모드):
SCREENBRIDGE_USE_LOCAL=1 ./dev.sh
첫 ⌥+Space → ~2GB Hugging Face download (5-10분)
ModelDownloadProgress UI 박힘 → ⌘, → Settings 안 진행률 봄
다운 후 → 100% Mac 안에서만 동작

# Settings UI:
⌘, → Privacy mode (auto/cloud/always-local) 선택 + 재시작 적용
⌘, → Local Model section 안 download 진행률

# Inspector UI:
⌥⌘I → 별도 panel 떠 (multi-monitor follow)
  Header: dispatcher chip + privacy badge (cloud/local/blocked)
  Steps list: #1/#2/... 박은 거 실시간
```

### 남은 v0.3 박을 거

```
Week 1 남은 거:
  🔲 fixtures/sensitive_screens/*.png (사용자 본인 환경 5장)
  🔲 Probe D-prime 실 측정 — Qwen vs Gemini accuracy → GO/NO-GO

Week 2:
  🔲 어머님 M1 8GB 실측 (Slack/카톡/메모 3 시나리오)
  🔲 WWDC26 keynote (6/8-12) Apple FM vision 발표 watch

Week 3:
  🔲 Region drag UI (사용자가 *영역 그림* — NSWindow overlay + drag handler)
  🔲 Apple Developer Program enrollment ($99/년)
  🔲 .app bundle + Info.plist + codesign
  🔲 Notarization pipeline (notarytool submit + staple)
  🔲 Sparkle integration (appcast.xml + EdDSA)

Week 4:
  🔲 Beta DMG 박음 + landing "Download" CTA
  🔲 GitHub Actions 자동 sign + notarize pipeline
  🔲 어머님 + 5-10 개발자 친구 배포 + 피드백
  🔲 v0.3 SHIPPED commit
```

박힌 거 (이번 burst):
- 9 commits × ~2-3h 박는 시간
- 5-layer 보안 5/5
- Settings UI + Inspector UI + Download UI
- 150 tests pass
- DMG path 결정 (Mac App Store SKIP)

→ v0.3 ship까지 *진짜 가깝게* 박힘.

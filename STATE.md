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
- [x] Swift Phase 2.1 — AnalysisResult Codable struct (이 commit): snake_case CodingKeys 명시 (R9), `coordinates: [Int]?` optional (OCR fallback only — 번역기 본질 "99% 좌표는 OCR source"), `raw`는 Codable 분리 + `withRaw(_:)` builder (R9, `responseSchema` 1:1 보존). 6 tests 통과 (`swift build` 1.41s, `swift test` 0.002s).

**Last commit:** Phase 2.1 (hash 다음 commit에 갱신)
**검증 안 됨:** `swift run` 실제 smoke (menu bar 아이콘 + ⌥Space → panel). 사용자 manual 필요 — GUI라 agent가 직접 못 띄움.

## Next step (다음 세션 시작점)

**Phase 2.x — LLM dispatcher (Swift)** — 2026-05-29 sweep workflow advice 반영 (AnalysisResult 첫, dispatcher 다음, Phase 5.0 빈 골격 끼움, OCR forward declare):

1. ✅ Phase 2.1 — `Sources/ScreenBridge/AnalysisResult.swift` Codable struct. **완료** (이 commit).
2. **Phase 2.2 (다음)** — `Sources/ScreenBridge/Prompts.swift` SYSTEM_PROMPT 한국어 + `target_text` 필수 + ✗/✓ 페어 (Tauri Layer 16 학습 직역) + "여기 [버튼명] 누르세요" 비-AI-native 친화 톤. + `Sources/ScreenBridge/Env.swift` `GEMINI_API_KEY` 로드 (ProcessInfo + .env 폴백, dep 0).
3. Phase 2.3 — `Sources/ScreenBridge/LLMDispatcher.swift` (protocol) + `GeminiDispatcher.swift` (URLSession POST `gemini-2.5-flash:generateContent`, `responseMimeType`+`responseSchema` 강제, `timeoutInterval=30`, retry 429/500/503 exp backoff max 3). + `Tests/.../GeminiDispatcherTests.swift` fixture-based (`XCTSkipUnless GEMINI_API_KEY`).
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

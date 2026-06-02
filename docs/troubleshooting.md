# Troubleshooting log

Issues hit and the fix for each. Newest at the bottom.

Format for each entry: **Symptom** · **Cause** · **Fix** · **Commit** · (optional **Pattern**).

When you fix a non-trivial issue, append an entry below. The Stop hook in `.claude/settings.json` reminds about this after any recent commit.

---

## How to add a new entry

```markdown
## <short title>

- **Symptom**: <literal error message or observable behavior>
- **Cause**: <verified explanation> (or `Hypothesis: ... Verified by: ...`)
- **Fix**: <files/functions changed, mechanism>
- **Commit**: <hash from `git rev-parse HEAD` AFTER committing>
- **Pattern**: <one-line recurring lesson — optional>
```

Concrete only. Numbers, file paths, commit hashes. No "lessons learned" essays.

---

## Tauri overlay 윈도우가 fullscreen 흰색으로 화면 가림

- **Symptom**: `npm run tauri dev` 후 흰색/회색 윈도우가 화면 전체. dev 콘솔도 가려져서 종료 어려움.
- **Cause**: `tauri.conf.json`에 `"fullscreen": true` + `"visible": false`. macOS는 fullscreen을 별도 Space로 그리면서 `visible:false`보다 먼저 paint. 추가로 `"transparent": true` + `macos-private-api` Cargo feature 미설정 → transparent 무력화 → 흰색.
- **Fix**: `tauri.conf.json` fullscreen 제거 + width:1/height:1. setup hook에서 `w.hide()` + `w.set_ignore_cursor_events(true)`. config `macOSPrivateApi:true` + Cargo `features=["macos-private-api"]` 둘 다. frontend가 listen 시 monitor 사이즈로 setSize.
- **Commit**: `a4a76f6`, `ed7c39f`
- **Pattern**: Tauri transparent는 macOSPrivateApi (config + feature) 둘 다 필요. macOS NSWindow는 `.isOpaque=false; .backgroundColor=.clear` 두 줄.

---

## Tauri capability `windows:["main"]`이 새 라벨 안 잡음 (silent fail)

- **Symptom**: `tauri-plugin-global-shortcut` Alt+Space 등록 성공, backend가 `trigger pressed` 잘 찍는데 frontend의 `listen()`이 한 번도 발화 안 함.
- **Cause**: Tauri 2 capability는 윈도우 라벨 기준 매칭. 우리 라벨 `trigger`/`overlay`인데 default capability windows는 `["main"]`. 라벨 안 맞으면 default permission 적용 X.
- **Fix**: `capabilities/default.json`의 `"windows": ["trigger", "overlay"]`.
- **Commit**: `a4a76f6`
- **Pattern**: Tauri 2 capability는 라벨 매칭 silent fail. window 라벨 변경 시 capability 동시 update.

---

## Tauri `core:default`가 `window.show` 자동 미포함

- **Symptom**: capability 라벨 fix 후 `win.show()`에서 silent throw. try-catch로:
  ```
  window.show not allowed. Permissions associated with this command: core:window:allow-show
  ```
- **Cause**: Tauri 2 v2.0+에서 보안 강화. `core:default`는 안전한 기본만. show/hide/setFocus/setPosition/setSize/setIgnoreCursorEvents/currentMonitor 같이 *상태 변경* 메서드는 명시적 allow.
- **Fix**: capability에 8개 권한 명시 (`core:window:allow-show`, allow-hide, allow-set-focus, allow-set-position, allow-set-size, allow-set-ignore-cursor-events, allow-current-monitor, `core:event:allow-emit`, allow-listen).
- **Commit**: `a4a76f6`
- **Pattern**: Tauri 2 capability는 default-deny. 에러 메시지의 `Permissions associated with this command: <key>`가 추가할 권한 이름.

---

## Tauri webview `:root background`가 overlay 흰색 가림

- **Symptom**: transparent + click-through 박은 후에도 사용자 "여전히 가린다" 반복.
- **Cause**: `App.css`의 `:root { background-color: #f6f6f6 }`가 같은 React 번들 로드하는 *overlay webview*까지 흰색 칠함. Tauri `transparent:true`는 webview content가 transparent여야 의미 있음.
- **Fix**: `:root background: transparent` + `html, body { background: transparent }` + `.trigger-panel`에만 색 + dark mode 동일 패턴.
- **Commit**: `ed7c39f`
- **Pattern**: multi-window Tauri에서 transparent + 색 윈도우 한 React 번들 공존 시 :root/html/body에 색 두지 말 것.

---

## DPR 4-layer 좌표 변환 (Retina 함정)

- **Symptom**: 좌표 변환 다 박았는데 빨간 박스가 의도 위치의 2배 멀리.
- **Cause**: 4-layer 중 CSS logical 한 단계 빠뜨림. capture physical (3456×2234) → 다운스케일 sent (1568×1014) → monitor physical (3456×2234) → CSS logical (1728×1117). 마지막 /DPR 안 함.
- **Fix**: Overlay.tsx가 `currentMonitor().scaleFactor` → dpr 저장. 모든 coords / dpr 후 CSS 적용. bubble 위치 동적 (박스 옆 또는 화면 중앙).
- **Commit**: `4c38f73`
- **Pattern**: 좌표 layer 4단계. 각 단계 명시 안 하면 한 군데 빠뜨림. macOS native는 `NSScreen.convertRect(_:from:)` 한 함수.

---

## reqwest default timeout 없음 → 3분 hang

- **Symptom**: Gemini schema 박은 후 첫 호출. `begin` 라인 후 `ok`/`fail` 없음 3분+ (사용자가 hang 인식).
- **Cause**: `reqwest::Client::builder().build()`는 default timeout 없음. 서버 응답 안 주면 영원히 await.
- **Fix**: `HTTP_TIMEOUT=60s` 상수 + 모든 reqwest Client (AnthropicDispatcher/GroqDispatcher/GeminiDispatcher)에 `.timeout(HTTP_TIMEOUT)`.
- **Commit**: `4674914`
- **Pattern**: 모든 외부 HTTP 호출 timeout 명시. reqwest default 무한대가 함정.

---

## Gemini free-form 응답 → responseSchema 강제

- **Symptom**: Gemini 3회 호출 중 2회 parse 실패. raw_len 173-174의 짧은 응답이 free-form 텍스트로 옴.
- **Cause**: Gemini는 `responseMimeType: "application/json"` + `responseSchema`로 *강제* JSON. SYSTEM_PROMPT 텍스트만으로 "JSON으로 답해"는 비결정적. Anthropic sonnet은 99%+ JSON 출력하지만 Gemini는 느슨함.
- **Fix**: `generationConfig`에 `responseMimeType: "application/json"` + 명시적 schema (screen_state/next_action/coordinates/reasoning + target_text required).
- **Commit**: `1428843`
- **Pattern**: vendor별 strict JSON 메커니즘 다름 — Anthropic SYSTEM_PROMPT만, Gemini responseSchema, Groq json_object, OpenAI response_format json_schema.

---

## Groq Llama 4 Scout 17B vision 실측 76초 (예상 1-5초)

- **Symptom**: SB_DISPATCHER=groq 시도. 76,625ms (76초). claude CLI 41초의 2배. 좌표 인식 실패 (`coords=None`).
- **Cause**: WebSearch의 Groq sub-200ms TTFT / 300-1000 tps는 *텍스트 모델* (Llama 3.3 70B 등) 기준. Vision은 image encoder + token generation 두 단계 — preview Llama 4 Scout 17B는 vision LPU pipeline 최적화 부족 가능. 1MB PNG base64 ~1.3MB 업로드 시간 추가.
- **Fix**: dispatcher 비교 매트릭스 (`DECISIONS.md`) — Groq 후보 폐기. Gemini Flash 채택.
- **Commit**: `358e54f` (실측 기록)
- **Pattern**: 텍스트 inference 벤치마크를 vision에 외삽 X. WebSearch 결과 인용 시 어느 모달리티 측정인지 확인 필수.

---

## multi-monitor: primary 아닌 cursor monitor 캡처 (+ hotkey 시점 cursor)

- **Symptom**: 사용자 multi-monitor (Chrome 왼쪽, VS Code 오른쪽). 빨간 박스가 VS Code monitor 우상단 빈 영역. OCR miss + LLM 좌표 잘못된 위치.
- **Cause**: `monitors.iter().find(|m| m.is_primary())` 만 — 사용자가 본 화면 아님. 또 analyze 시점 cursor를 쓰면 panel 활성 후 cursor가 panel monitor로 이동 → capture가 또 잘못된 monitor.
- **Fix**: `core-graphics` crate + `CGEventSource::location()`으로 cursor logical position. `Monitor::from_point(cursor)` → 사용자 본 monitor. + `LAST_TRIGGER_CURSOR` static에 hotkey/tray callback에서 *⌥+Space 시점* cursor 저장. analyze가 stored cursor 우선 사용.
- **Commit**: `cf4ea23`, `ea7390e`
- **Pattern**: cursor position이 "사용자가 본 화면"의 proxy. 단 *시점*이 결정적 — 입력 stream 시작점 (trigger) 시점이 intent의 가장 명확한 signal.

---

## Rust sessions test struct literal 누락 (cargo check 통과, cargo test 실패)

- **Symptom**: `cargo check`는 통과, `cargo test`에서 `E0063: missing field session_dir`.
- **Cause**: `cargo check`는 default profile만. `#[cfg(test)]` 모듈은 test profile에서만. AnalysisResult에 새 field 추가하고 check만 돌리면 test 모듈의 struct literal이 통과한 척.
- **Fix**: `..Default::default()`를 struct literal 끝에. 회복력 룰 R4에 `cargo test --no-run` 권장 추가.
- **Commit**: `daf6a5e`
- **Pattern**: Rust cargo check ≠ test profile compilation. 새 field/필수 인자 추가 시 둘 다 검증.

---

## Tauri macOS HUD attempt — 16 layer trial-and-error 후 Swift swap

- **Symptom**: ScreenBridge v0.1을 Tauri 2 + Rust + WebView로 박는 동안 macOS-native HUD 카테고리의 layer를 매번 1-2 commit씩 발견. 총 16개. dogfooding 진입까지 비용 큼.
- **Cause**: Tauri는 cross-platform desktop app framework이지 macOS-native HUD 카테고리 (Apple SDK가 표준 패턴 정해놓은) 도구 아님. `NSWindow.collectionBehavior`, `NSScreen.convertRect`, `AXUIElement` 같은 SDK 한 줄짜리를 Tauri 추상화 위에 매번 재발견.
- **Fix**: main을 Swift macOS native (SwiftPM + SwiftUI + AppKit)로 swap. Tauri 코드는 `tauri-archive` branch + `v0.1-tauri-attempt` tag로 영구 보존.
- **Commit**: `32929bd` (main reset), `571e213` (Swift Phase 0.1)
- **Pattern**: stack 선택은 *product 카테고리*와 framework sweet spot의 match가 우선. cross-platform 욕심이 native-only 제품에 비싼 trade-off.

---

## Swift 6 strict concurrency — deinit에서 @MainActor property 접근 불가

- **Symptom**: HotKeyManager (@MainActor)에 Carbon hotkey cleanup deinit 넣으니 `swift build` 에러:
  ```
  error: cannot access property 'eventHandler' with a non-Sendable type 'EventHandlerRef?' (aka 'Optional<OpaquePointer>') from nonisolated deinit
  ```
- **Cause**: Swift 6 strict concurrency (language mode v6). `@MainActor` class의 `deinit`은 nonisolated가 기본. @MainActor-isolated stored property (`eventHandler`, `hotKeyRef`)를 deinit에서 접근 불가.
- **Fix**: deinit 제거. cleanup을 별도 `unregister()` @MainActor method로. HotKeyManager는 앱 lifetime 내내 살아있어 process 종료 시 OS가 global hotkey 자동 해제 — deinit cleanup 사실상 불필요.
- **Commit**: `63c0568`
- **Pattern**: Swift 6 @MainActor class의 deinit은 nonisolated — isolated property 접근하려면 별도 @MainActor method. lifetime-long object는 OS 정리에 맡기고 cleanup 생략 가능.

<!-- macOS Carbon (deprecated) global hotkey가 Swift 6에서도 정상 동작 — InstallEventHandler + RegisterEventHotKey. C function pointer 콜백은 Unmanaged로 self 전달. -->

---

## AnalysisResult: LLM 응답 schema 1:1 + raw는 dispatcher가 후채움 (Phase 2.1)

- **Symptom**: LLM dispatcher 응답에 raw text도 보관해야 하는데, raw를 struct에 포함하면 Gemini `responseSchema`와 LLM JSON엔 raw 키가 없어 mapping 의미 모호.
- **Cause**: `AnalysisResult` Codable shape이 곧 LLM의 `responseSchema`. raw는 LLM이 채우는 게 아니라 dispatcher가 채우는 메타데이터 → schema에 섞이면 안 됨.
- **Fix**: raw를 stored property로 두되 `CodingKeys`에서 제외 + custom `init(from:)`/`encode(to:)` + `withRaw(_:)` builder. dispatcher가 decode 후 raw 주입.
- **Commit**: `e075f0f`
- **Pattern**: LLM 응답 struct의 Codable shape = vendor responseSchema. 메타데이터(raw, latency 등)는 Codable 밖 + builder로 후주입.

---

## SYSTEM_PROMPT의 ✗/✓ 페어가 visible-text 룰을 강제 (Phase 2.2)

- **Symptom**: LLM이 `target_text`에 임의로 번역/축약한 라벨 ("auth button", "로그인 버튼")을 넣어 OCR matcher가 화면 텍스트와 substring 매칭 못 함 (Tauri Layer 16 재발 위험).
- **Cause**: SYSTEM_PROMPT 텍스트 룰만으론 LLM이 "한 글자도 바꾸지 마라"를 안 지킴. 추상↔구체의 *경계*를 예시로 보여줘야 학습.
- **Fix**: SYSTEM_PROMPT에 ✗/✓ 페어 4 × 2 직역. 예: `"auth button"` ✗ vs `"Sign in"` ✓, `"the create button"` (군더더기 `the`) ✗ vs `"Create API Key"` ✓, `"settings icon"` (아이콘 = 텍스트 없음) ✗ → `coordinates` 사용. PromptsTests에 ✗/✓ literal 포함 검증 — silent drift 차단.
- **Commit**: `f7b799b`
- **Pattern**: vision LLM의 "visible text 정확" 룰 = 텍스트 룰 + ✗/✓ 예시 페어 둘 다. 예시 없으면 LLM이 자기 판단으로 라벨 정규화 → backend OCR matcher 실패.

---

## Swift 6 struct 자기참조 → "infinite size" build 에러 (Phase 2.3)

- **Symptom**:
  ```
  error: value type 'JSONSchema' cannot have a stored property that recursively contains it
  error: value type 'GeminiGenerationConfig' has infinite size
  note: cycle beginning here: JSONSchema -> (items: JSONSchema?) -> (some(_:): JSONSchema)
  ```
- **Cause**: `struct JSONSchema { let items: JSONSchema? }` — Swift는 value type 자기참조 stored property 금지 (Optional 이라도 size 무한). Swift 6 strict mode 동일.
- **Fix**: `indirect enum JSONSchema { case string, integer, array(items: JSONSchema), object(properties: [String: JSONSchema], required: [String]) }`. `indirect` keyword가 reference indirection 추가 → finite size. case 구분으로 *어느 type엔 어떤 field*가 더 명확.
- **Commit**: (Phase 2.3 — 다음 commit에 hash 갱신)
- **Pattern**: Swift value type이 자기참조 하려면 `indirect` 또는 `final class` wrapper. recursive data structure (JSON schema, tree node 등)는 enum + indirect가 깔끔.

---

## HotKeyManager OSStatus discard → silent fail (Phase 2.3)

- **Symptom**: Phase 0.2 sweep audit 발견 — `InstallEventHandler` / `RegisterEventHotKey` 반환 OSStatus 무시. 다른 앱(Alfred/Raycast/Klack/한영 전환기 등)이 ⌥+Space 점유하면 사용자 ⌥Space 눌러도 panel 안 뜸 + log 0.
- **Cause**: Carbon API 반환값 discard.
- **Fix**: `let registerStatus = RegisterEventHotKey(...)` capture + 성공 시 `Log.hotkey.info("registered ⌥+Space")`, 실패 시 `Log.hotkey.error("OSStatus=\(registerStatus, privacy: .public) — Alfred/Raycast/Klack 등 점유 가능")`. 사용자가 `log stream` 으로 즉시 진단.
- **Commit**: `8a60c2f`
- **Pattern**: C API (특히 Carbon) 반환값은 *반드시* capture + 에러 시 명시 log. Silent fail은 사용자 못 봄 → debug burden 폭증.

---

## Swift 6 strict concurrency가 extern var `kAXTrustedCheckOptionPrompt` 거부 (Phase 3.1)

- **Symptom**: build 시:
  ```
  error: reference to var 'kAXTrustedCheckOptionPrompt' is not concurrency-safe
         because it involves shared mutable state
  note: var declared here (AXUIElement.h: extern CFStringRef kAXTrustedCheckOptionPrompt)
  ```
- **Cause**: Swift 6 strict concurrency가 C `extern var`를 mutable shared state로 간주. `kAXTrustedCheckOptionPrompt`는 Apple HIServices가 노출한 `CFStringRef` extern — Swift 측 marking 없어 거부.
- **Fix**: string literal로 대체 — `"AXTrustedCheckOptionPrompt"` (Apple 공식 const string과 동일). `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)`. 의미 동일, concurrency-safe.
- **Commit**: `7f4d4f4`
- **Pattern**: Swift 6 strict concurrency가 C `extern var` 또는 unannotated mutable state 막을 때 — Apple 표준 const string은 literal로 대체 가능 (Apple stability 보장). 또는 `nonisolated(unsafe) let wrapper = ...` 패턴.

---

## SCContentFilter empty `excludingWindows: []` → SCStream buffer stall (Phase 3.1 verify fix)

- **Symptom**: ScreenCaptureKit `SCContentFilter(display:excludingWindows:)`에 empty array 전달 — SCStream produces no buffers, capture silently fails. 사용자 ⌥Space → analyze 100% 깨짐 (verify workflow BLOCKER finding).
- **Cause**: Documented bug (Federico Terzi: https://federicoterzi.com/blog/screencapturekit-failing-to-capture-the-entire-display/). Apple 공식 sample (`CapturingScreenContentInMacOS`)은 이 initializer 피함.
- **Fix**: `SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])`. 동일 의미 (전체 display, 모든 app, 예외 없음) — but Apple-sanctioned shape이라 buffer stall X.
- **Commit**: (Phase 3.1 verify fix — 다음 commit에 hash 갱신)
- **Pattern**: ScreenCaptureKit init variant 선택 시 Apple 공식 sample 우선. community 검증 reference (Federico Terzi 등) 학습 자산에 박아두기. solo 작성으로는 vendor SDK bug catch 어려움 — adversarial multi-agent review 가치.

---

## "NSScreen.main 절대 금지" 정신을 자기 fallback에서 위배 (Phase 3.1 verify fix)

- **Symptom**: `DisplayGeometry.swift:16` doc comment에 `⚠️ NSScreen.main 절대 금지 — Tauri Layer 9 회피` 명시. 그러나 `ScreenCapture.swift:39` + `TriggerContext.swift:32` fallback에 `?? NSScreen.main` 박혀있음 (자기 모순). cursor가 모든 screen 밖 rare path에서 hard rule 위반 → primary monitor 캡처 시도 → 잘못된 화면.
- **Cause**: 명시적 rule 박은 후 코드 작성 도중 fallback path에 *다시 박음*. solo 작성에서 매우 잡기 어려운 패턴 — verify workflow의 adversarial review가 catch.
- **Fix**: `?? NSScreen.screens.first` (macOS process는 최소 1개 screen 보장).
- **Commit**: (Phase 3.1 verify fix — 다음 commit에 hash 갱신)
- **Pattern**: 코드에 hard rule ("절대 금지") 명시 시 — fallback path를 의식적으로 review. 자기 모순 발견은 multi-agent adversarial workflow의 정확한 가치 영역.

---

## `logicalRectFromSentBox`가 screen-local만 반환 → 외부 monitor 함정 (Phase 3.1 verify fix)

- **Symptom**: `DisplayGeometry.logicalRectFromSentBox` screen-local top-left CGRect 반환. Phase 5 HUD가 그 결과를 `NSWindow.setFrame(_:)` 직접 호출 시 — 외부 monitor (`screenFrame.origin.x = 1440` 등)에선 *primary monitor*에 HUD 뜸. Tauri Layer 9 재발 100% 보장.
- **Cause**: `screenFrame.origin`이 helper에 입력으로 들어갔지만 반환값에 반영 X. 호출자가 "그대로 setFrame OK"라 가정.
- **Fix**: `globalAppKitRect(fromLocalTopLeft:) -> NSRect` helper 추가. `screenFrame.origin.x` add + y flip (`screenFrame.height - (local.origin.y + local.height)`) 한 곳. 3 unit tests (primary / 외부 monitor x=1440 / vertical stack origin.y=900)로 lock.
- **Commit**: (Phase 3.1 verify fix — 다음 commit에 hash 갱신)
- **Pattern**: 좌표 변환 helper가 partial conversion 반환 시 — 명시적 doc comment + 다음 단계 helper도 같이 제공. Phase 5 HUD code 작성 단계에서 산수 burden 없게. PR review에서 raw 결과 `setFrame` 직접 호출 패턴 차단.

---

## `codesign --identifier` 누락 → 매 build TCC 권한 재요청 loop (Phase 3.1 verify fix)

- **Symptom**: `swift build` + `codesign --force -s -` ad-hoc signed binary. 매 build cdhash 변경 → TCC가 binary 정체성을 *다른 binary*로 인식 → 매 `./dev.sh`마다 Screen Recording 권한 다이얼로그 재출현. 사용자 좌절 흐름 직역.
- **Cause**: codesign에 `--identifier` 명시 없음 → TCC가 binary path + cdhash 조합으로만 식별 → 일관성 깨짐.
- **Fix**: `codesign --force --sign - --identifier com.screenbridge.dev "$BIN_PATH"`. `--identifier` 명시로 TCC가 identifier + cdhash 조합 기억 → 한 번 권한 부여 후 매 build 유지.
- **Commit**: `131da7b`
- **Pattern**: macOS TCC dev iteration에서 `swift run` + ad-hoc codesign 패턴 사용 시 — 반드시 `--identifier <stable-id>` 명시. 미명시 시 매 빌드 권한 dialog loop. 중기 swift-bundler/Xcode `.app` bundle로 이행 시 `Info.plist` `CFBundleIdentifier`가 같은 역할.

---

## Swift 6 implicit self in `os.Logger` string interpolation (Phase 4.2)

- **Symptom**: `error: implicit use of 'self' in closure; use 'self.' to make capture semantics explicit` — `Log.app.info("... \(contentKind(content), privacy: .public) ...")` 같은 패턴.
- **Cause**: `os.Logger` string interpolation의 `\(...)` arguments는 *escaping autoclosure*로 평가됨 (지연 evaluation — log level filtering 시 호출 안 함). Swift 6 strict concurrency는 escaping closure 안 instance method/property 접근 시 `self.` 명시 강제.
- **Fix**: `self.contentKind(content)` — 명시. 변수/literal은 영향 없음, *instance method/property*만.
- **Commit**: `1862076`
- **Pattern**: `os.Logger` interpolation 안에서 method 호출 또는 instance property 사용 시 — Swift 6에서 `self.` 명시 강제. (`Log.X.info("\(self.method(), privacy: .public)")`). plain literal/변수는 무관.

---

## Gemini 2.5 Flash latency: 가설 8-15s vs 실측 2.4s (Phase 4.2 첫 dogfooding)

- **Symptom (긍정적 surprise)**: 사용자 첫 `./dev.sh` analyze — 가설 8-15s vs **실측 2.4s** (capture 0.1s + Gemini 2.3s). HUD "분석 중..." spinner 잠깐 보임.
- **Cause**: Gemini 2.5 Flash가 vision multimodal에서 sweep workflow agent의 docs 인용 추정보다 빠름. 692KB PNG (1568×1014 다운스케일) → 2.3s.
- **Fix**: 가설 갱신. Phase 5.x bubble UI 작성 시 latency 가설 = **2-5s** (8-15s 아님). loading message 친화 톤 가능 (`"AI한테 물어보는 중..."` 등) — 사용자 burden 작음. PROJECT_TIMELINE에 실측 자료 박음.
- **Commit**: (Phase 4.2 fix — 다음 commit에 hash 갱신)
- **Pattern**: vendor SDK latency 가설은 sweep agent의 docs 인용만으론 실측과 다를 수 있음. *첫 dogfooding 호출이 결정적 자료* — 가설을 lock하지 말고 실측으로 갱신.

---

## LLM이 SYSTEM_PROMPT "fallback only" 룰 잘 따라 OCR 매칭 의존, OCR 없으면 epoch fail (Phase 4.2 fix)

- **Symptom**: 사용자 첫 분석 시도 — 모든 호출이 "이 화면에선 정확한 위치를 못 찾았어요" 에러. log: `[analyze] no coordinates from LLM — OCR matcher (Phase 6.1) 필요`.
- **Cause**: SYSTEM_PROMPT(Phase 2.2)가 "`coordinates`는 fallback only. 평소엔 키 생략 — backend OCR가 `target_text`로 위치 정확히 찾는다" 명시 → LLM이 좋은 시민으로 키 생략. 그러나 Phase 6.1 OCR matcher 미작성 → AppDelegate.handleAnalyze의 fallback branch가 매번 trigger.
- **Fix (v0.1 임시)**: Prompts.swift SYSTEM_PROMPT 룰 swap (`fallback only` → `반드시 줘 (v0.1)`) + GeminiDispatcher responseSchema `required`에 `coordinates` 추가 + tests 업데이트. Phase 6.1 commit 시점에 다시 swap. DECISIONS R9 entry.
- **Commit**: `e674aea`
- **Pattern**: SYSTEM_PROMPT 룰과 backend 구현 *gap*은 dogfooding 전엔 안 보임. LLM이 *너무 잘* 룰 따르면 — 룰이 미래 구현에 의존하는 경우 첫 호출이 전부 fail. 임시 fix + Phase 마일스톤 동기화.

---

## Vision OCR 좌표계 Y-flip — normalized bottom-left → sent image top-left (Phase 6.1)

- **Symptom**: `VNRecognizedTextObservation.boundingBox`는 normalized 0..1 *bottom-left* origin. 그대로 sent image px (top-left origin)로 곱하면 Y축 뒤집힘 — 박스가 위/아래 거꾸로.
- **Cause**: Vision framework 좌표계는 *Core Graphics/SwiftUI* (bottom-left) 표준. CGImage / SCScreenshotManager 결과는 top-left. ElementMatcher는 sent image 좌표계 (top-left, DisplayGeometry와 일관) 가정.
- **Fix**: OCRService에서 변환 한 줄로 명시 — `y = (1.0 - bb.maxY) * h`. `bb.maxY` 사용 이유: bottom-left bbox는 위쪽 모서리가 `maxY` (높은 y) → top-left에선 위쪽 모서리가 작은 y. 1에서 빼면 top-left y 좌표.
- **Commit**: `95d4c57`
- **Pattern**: Vision framework 좌표계 변환은 *한 곳*에서. 여러 곳에 흩어지면 top-left/bottom-left mix 함정 (Tauri Layer 6 유사). DisplayGeometry의 4-layer 변환과 일관 — `OCRService.recognize`가 sent image px (top-left) 반환, `ElementMatcher`가 그걸 `DisplayGeometry.logicalRectFromSentBox`로 logical pt 변환.

---

## ElementMatcher Unicode NFC/NFD silent mismatch — 한국어 매칭 fail (Phase 6.1 verify fix)

- **Symptom**: 한국어 화면에서 LLM `target_text`와 OCR 결과가 *동일한 글자*인데 `ElementMatcher` 매칭 fail. 예: `"한글 메뉴"` target이 `"한글 메뉴"` box를 못 잡음.
- **Cause**: macOS HFS+/APFS filename은 NFD(자모 분해, `ㅎ+ㅏ+ㄴ`)로 저장되고 Finder UI/OCR은 NFC(완성, `한`)로 표시되는 경우 흔함. Swift String `==`은 canonical equivalent로 같다고 인식하지만, **codepoint-level 비교** (`unicodeScalars`)는 다름. ElementMatcher의 Levenshtein 안 `Array<Character>` 비교가 *grapheme cluster* 기반이지만, 디버그 trace 어려움 + 정규화 누락 자체가 future risk.
- **Fix**: `normalize()` 시작에 `.precomposedStringWithCanonicalMapping` 호출 (NFC 강제). defensive measure. Test가 `Array(s.unicodeScalars)` 비교로 sanity 검증.
- **Commit**: (Phase 6.1 verify fix — 다음 commit에 hash 갱신)
- **Pattern**: 한국어/일본어/베트남어 등 conjoining script 매칭 시 항상 NFC normalize 명시. Swift String `==`이 자동 처리하지만, codepoint 비교 (Array<UnicodeScalar>), Levenshtein, OCR 외부 source는 별도 보장 필요.

---

## ElementMatcher punctuation strip — md vs txt 다른 파일 정확 reject (Phase 6.1 verify fix)

- **Symptom**: `target_text="CLAUDE.md"` 검색 시 OCR 결과 `"CLAUDE md"` (점 drop) 박스 매칭 fail. 반대로 `"CLAUDE.txt"` 박스가 0.78 sim으로 잘못 매칭.
- **Cause**: substring 매칭은 punctuation 일치 요구 — OCR이 흔히 `.`, `,`, `:`, `·` 같은 typographic chars 누락 또는 다르게 인식. fuzzy fallback도 punctuation 차이로 sim 낮아짐.
- **Fix**: `normalize()`에서 `CharacterSet.punctuationCharacters` strip. `"CLAUDE.md"` → `"claudemd"`, `"CLAUDE md"` → `"claudemd"` → substring 매칭. 단 `"CLAUDE.md"` vs `"CLAUDE.txt"` strip 후 `"claudemd"` vs `"claudetxt"` 여전히 다름 → 정확히 reject (다른 파일).
- **Commit**: (Phase 6.1 verify fix — 다음 commit에 hash 갱신)
- **Pattern**: 텍스트 매칭에서 punctuation은 OCR error의 가장 흔한 source. normalize 단계에서 strip — 정확도 ↑. 단 *의미 있는 punctuation 차이* (`.md` vs `.txt`)는 Levenshtein distance가 여전히 잡음 — 자동 reject.

---

## ElementMatcher 짧은 텍스트 fuzzy false positive — 'Save' vs 'Same' (Phase 6.1 verify fix)

- **Symptom**: `target_text="Save"` 검색 시 화면의 다른 단어 `"Same"`이 wrong-box로 잡힘. Levenshtein 1/4 = 0.75 ≥ 기본 threshold 0.7 → fuzzy 통과.
- **Cause**: 짧은 텍스트(≤6자)는 1자 차이 비율이 큼 — `"Save"` vs `"Same"` 0.75, `"Cancel"` vs `"Cancer"` 0.83. fuzzy 0.7 threshold는 *긴 텍스트*용 안전치. bubble UX는 매칭 박스를 직접 표시 → wrong-box가 가장 위험 fail mode.
- **Fix**: `ElementMatcher`에 `shortTextThreshold = 0.85` 추가. `normalizedTarget.count <= 6`이고 caller가 default threshold 사용 시 auto-tighten. 명시적 caller threshold는 그대로 (test용 escape hatch). `"Save"` vs `"Same"` 0.75 < 0.85 → reject.
- **Commit**: (Phase 6.1 verify fix — 다음 commit에 hash 갱신)
- **Pattern**: fuzzy threshold는 텍스트 길이에 비례 — 짧은 텍스트 stricter. 매칭 알고리즘의 false positive 비용 (wrong-box 표시) > false negative (사용자 다시 시도) — stricter 기본 안전.

---

## Vision sync cancel API 부재 — async let 빠른 fail 시 OCR implicit wait (Phase 6.1 verify, SDK 한계 인정)

- **Symptom**: `AnalyzeCoordinator`의 `async let dispatcherFuture + ocrFuture` 병렬에서 dispatcher 빨리 실패 시 — function return 전 `async let scope 종료` = `ocrFuture` implicit await. Vision sync는 끝까지 실행. 결과: `isRunning` defer는 풀리지만 *사용자 응답 지연*.
- **Cause**: `VNRequest`에 `.cancel()` API 없음 (Apple SDK 한계). `Task.checkCancellation()`은 `perform()` *시작 전*에만 체크 가능, perform 중간 cancel 무시. `Task.detached` → `Task` 변경으로 isolation 일관성 + cancellation signal 전달은 하지만, Vision sync는 그 signal을 무시.
- **Fix (부분)**: `Task.detached` → `Task` 변경 (parent isolation 상속, perform 전 `Task.checkCancellation` 체크). 미래 fix: `withTimeout(5s)` wrapper. 실측 mitigation: OCR latency (~1-2s) < dispatcher latency (3-4s) — 일반적으로 OCR이 먼저 끝남.
- **Commit**: `f08a603`
- **Pattern**: Apple SDK의 sync API는 cancel 불가능. async let scope 종료 시 implicit wait는 *Vendor SDK 한계 인정*. 완벽 fix는 timeout + best-effort cleanup. Phase 7+ 시점에 `withTimeout` 도입 검토.

---

## AXUIElement extern var들 Swift 6 strict concurrency 거부 (Phase 6.2)

- **Symptom**: `kAXRoleAttribute`, `kAXTitleAttribute`, `kAXPositionAttribute` 등 사용 시 — Phase 3.1의 `kAXTrustedCheckOptionPrompt`와 동일 에러:
  ```
  error: reference to var 'kAXRoleAttribute' is not concurrency-safe
  ```
- **Cause**: HIServices/AXUIElement.h의 모든 `extern CFStringRef` attribute 상수가 Swift 측 marking 없음 — Swift 6가 mutable shared state로 간주.
- **Fix**: Phase 3.1 lesson 적용 — string literal로 대체. Apple HIToolbox header의 const string과 동일:
  - `kAXRoleAttribute` → `"AXRole"`
  - `kAXTitleAttribute` → `"AXTitle"`
  - `kAXDescriptionAttribute` → `"AXDescription"`
  - `kAXValueAttribute` → `"AXValue"`
  - `kAXPositionAttribute` → `"AXPosition"`
  - `kAXSizeAttribute` → `"AXSize"`
  - `kAXChildrenAttribute` → `"AXChildren"`
- **Commit**: (Phase 6.2 — 다음 commit에 hash 갱신)
- **Pattern**: Apple HIServices/AXUIElement header의 모든 `kAX*Attribute` extern은 Swift 6에서 거부. struct에 `private static let` 로 string literal 모음 정의 후 caller가 사용 — 일관성 + maintainability. Apple stability 보장 (HIServices는 macOS 10.3+ stable).

---

## AXValue downcasting + AXValueGetType 사전 체크 (Phase 6.2)

- **Symptom**: AXUIElement에서 AXPosition/AXSize 추출 시 `CFTypeRef` → `AXValue` force cast가 위험. 잘못된 type이면 crash.
- **Cause**: AXUIElementCopyAttributeValue는 다양한 type 반환 (`String`, `Array`, `AXValue` 등). caller가 type 보장 필요.
- **Fix**: `as! AXValue` 후 `AXValueGetType(axValue) == .cgPoint` (또는 `.cgSize`) 사전 체크. type mismatch면 nil 반환.
- **Commit**: (Phase 6.2 — 다음 commit에 hash 갱신)
- **Pattern**: CFTypeRef downcasting은 항상 type check 동반. AXValue 같은 polymorphic container는 GetType 호출 후 안전한 GetValue.

---

## Single-shot 마다 재입력 좌절 → continuation scaffold (Phase 7.0)

- **Symptom**: "Slack에 메시지 보내" 같은 4-step task가 매 step ⌥+Space + instruction 재입력 → 사용자 quote: "그떄그떄 새로 치는게 너무 불합리하다".
- **Cause**: AnalyzeCoordinator가 *stateless single-shot* — 매 run() 이후 state 안 남김. AppDelegate.handleHotkey는 *항상* TriggerPanel 띄움.
- **Fix**: SessionState scaffold만 박음 (additive). AnalyzeRequest에 sessionID/previousSteps optional, AnalysisResult에 taskComplete/requiresConfirmation/stepActionSummary default false/nil, AnalyzeCoordinator에 SessionState enum + snapshotState/continueSession stub. *Behavior change X* — Phase 7.1에서 hotkey 분기 + HUD in-place swap + 45s idle timeout + IrreversibleActions post-filter wire.
- **Commit**: (Phase 7.0 — 다음 commit에 hash 갱신)
- **Pattern**: 큰 architecture 변화는 *scaffold-first* — additive 필드 + enum만 commit, behavior wire는 다음 commit. revert 비용 작게 (15분 안). Workflow design (4 trigger model 비교 + research + synthesis)으로 *과도 design 회피* — 가장 큰 ROI 답 (X hybrid) 자연 박힘.

---

## Gemini 429 retry burst + 실제 quota는 *일당 20회* (분당 X)

- **Symptom**: 사용자 dogfooding 중 "여러 번 시도했지만 실패" error 반복. log show 박힌 retry body:
  ```
  body={"message": "Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20, model: gemini-2.5-flash\nPlease retry in 29.667199528s.", "code": 429}
  ```
  retry-after는 *27-30초*로 짧게 박혀있지만, *daily counter는 PT midnight 후만 reset*. 그 안엔 *모든 call이 429*.
- **Cause**: Workflow 4-probe 진단 (w0dkpqbs2). Probe B (direct curl) 확정:
  - `quotaId: GenerateRequestsPerDayPerProjectPerModel-FreeTier`
  - `quotaValue: "20"` — gemini-2.5-flash 무료 *일당 20회* (per project per model)
  - CLAUDE.md "250 RPD"는 stale (Google이 2026 어느 시점에 250 → 20 silent 변경)
  - retry-after `27s`는 per-minute burst window 의미, *daily metric엔 무의미*
  - gemini-2.0-flash는 limit=0 (free-tier 0 할당)
  - 별도 client OK는 *paid tier 또는 다른 project key*
  - 우리 retry 1/2/4s exp backoff는 *daily-exhausted에 무의미* — 7초 안 3 retries → quota *더 빨리* burn
- **Fix (Phase 1 — partial)**: GeminiDispatcher.sendWithRetry에 `parseRetryAfterFromBody(_:)` regex 추가, body에서 `Please retry in <num>s` extract → 그 시간 respect (cap 60s, jitter). maxAttempts 3 → 2. UserMessage.retriesExhausted(lastStatus=429) 분리, 한국어 친화 "일일 한도 도달 — 내일 reset / GCP billing / 다른 project key" 3 옵션 안내. CLAUDE.md "250 RPD" → "20 RPD (2026-05)".
- **Fix (Phase 2 — TODO)**: body의 `RetryInfo`/`QuotaFailure` parse → *per-minute* (sleep + retry OK) vs *daily-exhausted* (fail fast, retry 무의미) 구분. daily 시 *Anthropic dispatcher fallback* 자동 swap (ANTHROPIC_API_KEY 있을 때). race condition (handleHotkey + handleContinuation Task spawn race) 별도 fix.
- **Commit (Phase 1)**: `8db0290` (retry-after respect) + 다음 commit (이번 — message 정정 + CLAUDE.md 갱신).
- **Pattern**:
  1. **Vendor docs는 silently 변경됨** — 250 RPD → 20 RPD가 *announce 없이* 적용. hardcoded 한도는 error response의 실제 값 사용.
  2. **Server가 retry-after 명시하면 무조건 respect** — exp backoff는 침묵 시 fallback.
  3. **Daily vs per-minute quota는 fix 전략 다름** — per-minute은 sleep+retry, daily는 fail fast + dispatcher swap.
  4. **별도 client OK 사용자 신호**는 *quota 도달 X*가 아니라 *다른 key/project/tier* — 같은 key 다른 client 의미 X.

<!-- skipped: 9e41b1d Add log entries for jarvis-pc (arch overview + 3 backfills) [no-log] -->
<!-- skipped: 0347be0 docs: 보안 deep dive blog (884 lines) + transferable playbook (1048 lines) -->
<!-- skipped: 4d57513 docs: local-first 로드맵 + 5-layer 보안 path 확정 (사용자 보안 우려 → 출시 가능 결정) -->
<!-- skipped: 2ffc163 v0.2: SecretMasker regex mask — 10 pattern (sk-/AKIA/ghp_/카드/주민번호) -->
<!-- skipped: a54b121 Phase 7.3: presentCompletion pill (초록 ✓) + SessionAuditLog JSON dump -->
<!-- skipped: dcb9164 Phase 7.2.1: hotkey 200ms throttle (Probe C race condition guard) -->
<!-- skipped: c412d6e backfill: 6 should-priority narrative entries (audit gap fill, 2 of 2) -->
<!-- skipped: 33fd37e Phase 7.2: Claude dispatcher + 429 자동 fallback (Gemini quota 우회) -->
<!-- skipped: ea77843 fix: Gemini quota 정정 — 일당 20회 (분당 X), CLAUDE.md 250 RPD stale -->
<!-- skipped: 364810b backfill: 4 must-priority narrative entries (audit gap fill) -->
<!-- skipped: 2506d59 Phase 7.1: continuation wire — hotkey 분기 + state transition + irreversible post-filter -->
<!-- skipped: c15578e perf: Gemini TLS/DNS pre-warm — 첫 analyze 호출 ~1-2s 단축 -->
<!-- skipped: f5a1261 feat: LLM target_role hint — schema-level AX role 명시 (multi-target 정확도 ↑) -->
<!-- skipped: 43a44ff feat: multi-target overlay — top 2 후보 + 번호 라벨 (user-in-the-loop 차별) -->
<!-- skipped: 62078ac fix: ElementMatcher prefer-only mode + AXService dock items log -->
<!-- skipped: 04430d7 docs: 📖 latency optimization playbook (612 lines transferable asset) -->
<!-- skipped: b5828c3 docs: 🚀 strategy update — pragmatic ship mode + target 확장 -->
<!-- skipped: c003829 Phase 5.x bubble: 한글 next_action + sourceTag + 화면 가장자리 clamping -->
<!-- skipped: cdd092b Phase 6.2 fix: SYSTEM_PROMPT 강화 (target_text 빈 string 금지 + intent-aware) -->
<!-- skipped: 5897394 docs: vision update — global + multi-platform + 5-layer security -->
<!-- skipped: fff55c5 dual-write log system 도입: docs/troubleshooting.md + content/logs/ -->
<!-- override-trigger: 58e688c docs: 59cc0cb troubleshoot + narrative entries (Stop hook trigger 풀이) — 이 commit 자체가 이전 commit 59cc0cb의 dual-write entries. 261 LOC가 threshold 넘긴 건 entry 자체 길이 (narrative mdx 256줄 + troubleshooting entry). dual-write에 또 dual-write 박는 건 무한 loop. -->
<!-- override-trigger: 9f2f43a feat: landing page 박음 (Apple-style + 어머님 + 빅테크 비교 + 5-layer 보안) — 1190 LOC threshold 넘긴 건 landing page asset 자체 (995 line HTML + 67 line README + 128 line narrative mdx). 이미 content/logs/jarvis-pc/2026-06-01-landing-page.mdx narrative entry 박힘 (이 commit 안). landing page는 *publishable artifact*이지 *troubleshoot* 아님 — troubleshooting.md fit X. R8 dual-write 정신 (narrative)는 박힘. -->

---

## MLXVLM Swift API drift — Workflow research vs pinned source (4 errors + 2 Swift 6 issues)

- **Symptom**: `swift build` 후 6 compile errors. workflow w02pv083c 박은 synthesis code sketch는 실제 mlx-swift-examples 2.21+ pinned source와 안 맞음:
  ```
  error: extra argument 'images' in call (UserInput init)
  error: value of type 'GenerateParameters' has no member 'topK'
  error: value of type 'GenerateCompletionInfo' has no member 'stopReason'
  error: cannot find 'Memory' in scope (MLX module)
  error: mutation of captured var 'raw'/'info' in concurrently-executing code (Sendable)
  error: reference to captured var 'params' (let needed)
  ```
- **Cause**: 4 issues.
  1. **API drift**: workflow synthesis 박은 *MLXLMCommon mlx-swift-lm 2026 변경* 박혀있음 — pinned mlx-swift-examples 2.21에서는 *images*는 `Chat.Message.user(_:images:)` 안에 박음 (UserInput.init은 images 별도 X).
  2. **topK 미노출**: pinned 2.21 GenerateParameters는 temperature/topP/maxTokens/repetitionPenalty만. topK는 박혀있지 않음.
  3. **GenerateCompletionInfo.stopReason 미노출**: pinned 2.21에는 promptTokenCount/generationTokenCount/promptTime/generateTime/tokensPerSecond/promptTokensPerSecond만.
  4. **MLX cache control**: workflow synthesis는 `Memory.cacheLimit = ...` 박혔는데 mlx-swift 0.29 path는 `MLX.GPU.set(cacheLimit:)`. `Memory` namespace 미박힘.
  + **Swift 6 strict concurrency**: container.perform { context in ... }은 *Sendable closure*. 외부 var (raw/info/params) mutation 또는 capture 모두 거부.
  - Verified by: `.build/checkouts/mlx-swift-examples/Libraries/MLXLMCommon/UserInput.swift`, `Evaluate.swift`, `Chat.swift` source 직접 grep + `.build/checkouts/mlx-swift/Source/MLX/GPU.swift`에서 `cacheLimit` 실제 path.
- **Fix**: `Sources/ScreenBridge/QwenLocalDispatcher.swift`에 4 fixes:
  1. `Chat.Message.user(instruction, images: [userImage])` — image를 chat 안에. `UserInput(chat:processing:)` 만.
  2. `topK` 삭제 — `temperature 0.0 + topP 0.001`로 effective greedy.
  3. `stopReason` 삭제 — `info.tokensPerSecond + generationTokenCount + promptTokenCount`만 log.
  4. `MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)` + `Package.swift`에 `mlx-swift 0.29.0+` 직접 dep 추가 (`.product(name: "MLX", package: "mlx-swift")` — mlx-swift-examples는 transitive resolve만, MLX product re-export X).
  5. Sendable closure: `let params = paramsBuilder` (immutable capture) + `container.perform { context -> (String, GenerateCompletionInfo?) in ... return (localRaw, localInfo) }` (tuple return).
- **Commit**: `59cc0cb`
- **Pattern**: Workflow research에서 박힌 *full code sketch*는 *최신 main branch source*인 경우 많음. 실제 `swift build` 전 `.build/checkouts/<pkg>/`에서 *pinned version source 직접 verify* 필수. 특히 빠르게 변하는 library (mlx-swift 2026 mlx-swift-lm split, MLXLMCommon API churn) 의존 시.
<!-- skipped: cd136a4 docs: override-trigger 58e688c (dual-write의 dual-write 무한 loop 차단) [no-log] -->
<!-- skipped: 1ec4e9d docs: override-trigger 9f2f43a (landing page asset, narrative 이미 박힘) [no-log] -->

---

## Qwen 박힌 dispatcher가 AppDelegate에서 호출 안 됨 (skeleton만 박힘 2일)

- **Symptom**: 2026-05-31 Phase 9.0 Week 1 skeleton (`26a1286`) + Week 2-3 wire (`59cc0cb`) 박혀있는데 *실제 호출 path X*. `AppDelegate.dispatcher` 결정 코드가 `GeminiDispatcher.fromEnvironment()` + `ClaudeDispatcher.fromEnvironment()` 만 보고 결정 — `QwenLocalDispatcher`는 *import만* 박혀있지 *생성 X*. 사용자 quote (2026-06-02): "존나 계속 가야지.. 페이즈9인데 아직도 제대로 안되네". 사용자가 *Phase 9 박힘 인식*하지만 *실제 작동 X* 인식.
- **Cause**: Phase 9.0 박는 흐름이 *skeleton → wire → AppDelegate 끼움* 3 단계인데 Week 1-2가 *skeleton + wire*에서 멈춤. 3 단계 (AppDelegate 끼움)는 *별도 commit*인데 *진행 안 함* → 사용자 입장에서 *Phase 9 박혀있어도 작동 X*.
- **Fix**: `Sources/ScreenBridge/AppDelegate.swift:18` — dispatcher 결정 갱신:
  - `Env.string("SCREENBRIDGE_USE_LOCAL") == "1"` 시 `QwenLocalDispatcher.make()` primary + cloud fallback (Claude 우선, Gemini fallback).
  - 그 외 = 기존 cloud-only path (Gemini + Claude fallback) 유지.
  - `FallbackDispatcher`의 generic type union을 위해 `cloudFallback: (any LLMDispatcher)? = claude ?? gemini.map { $0 }` 형식 박음 (Optional<Claude> ?? Optional<Gemini> = type mismatch → any LLMDispatcher 추론).
- **Commit**: `ef81ae6`
- **Pattern**: Phase 박는 흐름 3-step (skeleton → wire → AppDelegate 끼움)에서 *3번째* 빠뜨림이 *사용자 좌절 신호*로 박힘. 새 dispatcher / 새 service 박을 때 *minimum end-to-end wire*까지 같은 commit 또는 *바로 다음 commit*에 박는 게 *사용자 진척 인식* 안 깨뜨림.

---

## Gemini MAX_TOKENS hit + LLM "visible only" — Settings-like 큰 화면에서 step 끊김

- **Symptom**: 사용자 dogfooding ("github 알림 끄러 가자. 프로필 → settings → notifications" prompt) step 5에서 응답 끊김 + 사용자 quote "중간에 응답이 너무 길어요 하고 씹힌다 무조건 화면안에서만 찾으려해서그런가". `log show` 박힘:
  ```
  14:35:29 step=5 instruction 62 chars continuation=true
  14:35:29 [gemini] begin — image 212047 bytes (1024x662)
  14:35:41 [gemini] finishReason=MAX_TOKENS — response truncated, fail loud
  ```
- **Cause**: 2 원인.
  1. **maxOutputTokens 2048 부족** — Phase 6.1 speedup commit `d57a890`에서 8192→2048 줄였음. 단 Phase 7.0 `75a02ca`에서 `task_complete` + `requires_confirmation` + `step_action_summary` 3 schema field 박혔는데 *maxOutputTokens 갱신 안 됨*. Settings-like *큰 화면* (사이드바 + 본문 + 메뉴 동시) → LLM `reasoning` + `screen_state` + 8 field JSON → 2048 token 초과 → MAX_TOKENS error.
  2. **SYSTEM_PROMPT에 *스크롤 안내* clause 없음** — LLM이 *현재 visible 영역만* 분석. target이 *스크롤 영역* (Settings 사이드바 Notifications 같은) 있어도 인식 X → 사용자 좌절 "화면 안에서만 찾으려고".
  - Verified by: `/usr/bin/log show --last 10m --predicate 'subsystem == "com.screenbridge.app"' --info` 박힌 `finishReason=MAX_TOKENS` line + 사용자 quote 직접.
- **Fix**: 
  1. `Sources/ScreenBridge/GeminiDispatcher.swift:222` — `maxOutputTokens: 2048 → 4096` (2x margin). trade-off: 응답 짧으면 latency 동일, 길면 약간 ↑.
  2. `Sources/ScreenBridge/Prompts.swift` — 2 new clause:
     - **"응답 간결 룰"** (한 문장씩 / ≤30 단어 summary / JSON 밖 텍스트 X) — MAX_TOKENS 차단.
     - **"화면에 visible 안 보임 (스크롤 필요)"** — target_text = 현재 visible 가장 가까운 element + next_action = "여기 [X] 아래로 스크롤한 다음 다시 ⌥+Space 눌러주세요" + task_complete: false 유지 + step_action_summary에 "스크롤 필요" hint.
  3. `Tests/ScreenBridgeTests/PromptsTests.swift:45` — SYSTEM_PROMPT size budget 5000 → 7000 byte (5869 박힌 후).
- **Commit**: `f35b930`
- **Pattern**: Schema field 추가 시 *maxOutputTokens budget도 같이 확인*. Phase 7.0에 3 field 박았지만 maxOutputTokens 안 늘림 → 큰 화면에서 hit. 새 field 박을 때 *expected JSON size × 2*가 안전 margin.
<!-- skipped: f58f1de docs: f35b930 troubleshoot + narrative entries (MAX_TOKENS + scroll fix dual-write) [no-log] -->

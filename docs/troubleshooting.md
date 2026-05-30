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
- **Commit**: (Phase 2.3 — 다음 commit에 hash 갱신)
- **Pattern**: C API (특히 Carbon) 반환값은 *반드시* capture + 에러 시 명시 log. Silent fail은 사용자 못 봄 → debug burden 폭증.


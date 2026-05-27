# TROUBLESHOOTING

R8 (CLAUDE.md): 디버그하는 동안 발견 즉시 4-파트 엔트리. **사후 정리 금지** — 디버그 끝나면 그 commit에 포함.

엔트리 형식:
```markdown
## YYYY-MM-DD HH:MM — <짧은 제목>
**증상:** 사용자/터미널에서 관측된 현상.
**가설 / 시도:** 가능성 list, 어떤 순서로 시도했는지.
**원인:** 진짜 원인. 가설이 빗나갔으면 빗나간 이유까지.
**해결 + 학습:** 박은 fix와 한 줄 교훈. 다음 번에 같은 함정 피하는 신호.
```

---

## 2026-05-26 22:15 — `AnalysisResult` struct literal에 신규 필드 누락 (test profile에서만 잡힘)

**증상:** `cargo check`는 통과하는데 `cargo test`는 `E0063: missing field session_dir`로 빨강.

**가설 / 시도:** 처음엔 file write 누락 의심 → `git diff`로 cargo 의존성 + lib.rs 변경분 다 확인 → test 모듈만 struct literal 사용함을 발견.

**원인:** `cargo check`는 default profile만 빌드. `#[cfg(test)]` 모듈은 test profile에서만 컴파일. 새 필드 추가하고 default profile에서만 검증하면 test 모듈의 struct literal이 통과한 척한다.

**해결 + 학습:**
- Fix: `..Default::default()`를 literal 끝에 추가.
- 교훈: Phase commit 직전 `cargo test --no-run`까지 돌리면 test profile compilation도 같이 검증된다. 매번 full `cargo test`는 무거우니 `--no-run`이 좋은 절충.

---

## 2026-05-26 21:55 — Tauri 2 capability `windows: ["main"]`이 새 라벨 안 잡음

**증상:** `tauri-plugin-global-shortcut`로 Alt+Space 등록 성공, backend가 `trigger pressed` 잘 찍는데, frontend의 `listen()` 콜백은 *한 번도* 발화 안 함. 5번 단축키 눌러도 무반응.

**가설 / 시도:**
1. (틀림) 이벤트 이름의 `://` 콜론·슬래시 때문에 Tauri 내부 prefix와 충돌 → 단순 식별자 `sb-trigger`로 변경. 효과 0.
2. (틀림) React StrictMode가 useEffect 두 번 fire해서 listen unmount되는 거 → listen log를 박아서 확인했더니 등록은 정상.
3. (정답) `capabilities/default.json`의 `"windows": ["main"]`은 윈도우 라벨이 "main"인 webview만 capability 받음. 우리는 라벨을 `trigger`/`overlay`로 바꿔놨음.

**원인:** Tauri 2의 capability는 *윈도우 라벨* 기준 매칭. 라벨 안 맞으면 그 webview는 default permission(`core:default`, `core:event:default`)도 안 받는다. 그래서 frontend `listen()`은 silent fail.

**해결 + 학습:**
- Fix: `"windows": ["trigger", "overlay"]`로 변경.
- 교훈: `tauri.conf.json`의 윈도우 라벨을 바꾸면 *반드시* 모든 capability 파일의 `windows` 배열도 같이 손봐야 한다. 매핑이 라벨 문자열 매칭이라서 typo면 silent fail.

---

## 2026-05-26 22:18 — `core:default`가 `window.show` 권한을 자동 포함 안 함

**증상:** capability 라벨 fix 후 listen 동작 시작 (`listen FIRED` log 등장), 그러나 그 다음 `win.show()`에서 frontend가 silent throw. try-catch로 잡았더니:
```
window.show not allowed. Permissions associated with this command: core:window:allow-show
```

**가설 / 시도:**
1. `core:default`가 window 권한 다 포함한다 — 틀림. window 메서드는 default-deny.

**원인:** Tauri 2 v2.0+에서 보안 정책 강화. `core:default`는 안전한 기본만. `show`, `hide`, `setFocus`, `setPosition`, `setSize`, `setIgnoreCursorEvents`, `currentMonitor`, `event:emit`, `event:listen` 같이 *상태 변경* 메서드는 명시적 allow 권한 필요.

**해결 + 학습:**
- Fix: 사용하는 메서드 권한 다 명시:
  ```json
  "core:window:allow-show",
  "core:window:allow-hide",
  "core:window:allow-set-focus",
  "core:window:allow-set-position",
  "core:window:allow-set-size",
  "core:window:allow-set-ignore-cursor-events",
  "core:window:allow-current-monitor",
  "core:event:allow-emit",
  "core:event:allow-listen"
  ```
- 교훈: 에러 메시지의 `Permissions associated with this command: <key>`가 바로 추가할 권한 이름. capability JSON에 그 키 박으면 끝. 모든 frontend invoke가 같은 패턴 — 처음 한 번 다 박아두는 게 dogfooding 사이클 깨끗.

---

## 2026-05-26 22:10 — Overlay 윈도우가 `visible:false`인데도 fullscreen으로 화면 가림

**증상:** dev 띄우자마자 큰 흰색(혹은 회색) 윈도우가 화면 전체 가림. Trigger panel 못 봄. dev 콘솔도 가려져서 종료 어려움.

**가설 / 시도:**
1. (부분 맞음) `tauri.conf.json` `visible:false`가 dev 모드에서 무시됨.
2. (정답) `fullscreen:true` + `visible:false` 조합이 macOS에서 충돌. fullscreen은 macOS가 별도 Space로 그리면서 `visible:false`보다 먼저 paint.
3. 추가로 `transparent:true`만 두고 `macos-private-api` feature와 `macOSPrivateApi: true` config 둘 다 없으면 transparent도 작동 안 함 → 흰색 윈도우로 보임. backend 콘솔에 경고 한 줄 떴는데 그때는 못 봤다.

**원인:** 세 개가 합쳐진 케이크. fullscreen 무시 + private API 미적용 + visible 무시.

**해결 + 학습:**
- Fix:
  1. tauri.conf.json overlay 윈도우: `fullscreen:true` 제거, `width:1, height:1`로 작게 시작.
  2. `setup()` hook에서 명시적 `w.hide()` + `w.set_ignore_cursor_events(true)`.
  3. tauri.conf.json `app.macOSPrivateApi: true` + Cargo.toml `tauri = { features = ["macos-private-api", ...] }` 둘 다.
  4. `Overlay.tsx` listen 시점에 `currentMonitor()`로 모니터 사이즈 받아서 `setPosition(0,0) + setSize(w,h)` 다음 `show()`.
  5. `close()`에서 `setSize(1, 1)`로 다시 줄임.
- 교훈: macOS의 fullscreen은 "윈도우 가시성" + "별도 Space" + "private API"가 entangled. 처음부터 진짜 fullscreen 윈도우로 만들지 말고 작은 윈도우를 frontend에서 키우는 패턴이 안전. **backend 콘솔의 warning 한 줄을 매번 무시하지 말 것** — `The window is set to be transparent but the macos-private-api is not enabled` 메시지가 첫 시점에 있었으면 30분 아낌.

---

## 2026-05-26 22:00 — 좀비 process로 새 빌드가 stale binary와 충돌

**증상:** 사용자가 "재시작했는데 새 로그가 안 남는다"라 함. build.log 마지막 entry는 한참 전. 새 builder 코드 변경이 안 적용된 듯.

**가설 / 시도:**
1. tauri dev hot-reload 미작동 — 부분 맞음.
2. cargo lock 잡힘 — 부분 맞음.
3. (정답) 이전 dev session의 vite + Rust binary가 둘 다 살아 있어서 새 dev가 port 1420 충돌로 vite 못 띄움, 또는 Rust binary는 이전 코드 그대로 실행 중.

**원인:** `Ctrl+C`가 npm wrapper만 죽이고 자식 process (`tauri dev`, `target/debug/screenbridge`, `vite`)는 detach되어 살아남는 경우가 있음. 특히 한 번이라도 권한 다이얼로그 등으로 멈춘 적 있으면 더.

**해결 + 학습:**
- 진단: `lsof -i :1420` + `ps -ax | grep -E "screenbridge|tauri|vite"`.
- Fix: `lsof -ti :1420 | xargs kill; pkill -f screenbridge` 한 줄로 정리. 다시 `npm run tauri dev`.
- 교훈: dev 사이클이 이상하면 *항상* 좀비부터 의심. 다른 프로젝트의 `pnpm tauri dev`(다른 디렉토리)도 같은 OS-level 단축키 / port 경쟁 가능 — 멀티 프로젝트 셋업에선 정기적으로 ps 한 번씩.

---

## 2026-05-26 22:30 — `claude` CLI subprocess가 silent hang (실제: 즉시 종료)

**증상:** ClaudeCliDispatcher 박은 후 첫 Analyze. frontend "Analyzing…"에서 영원히 멈춤. backend log에 `claude-cli analyze begin` 줄은 있는데 `ok` 또는 `failed` 줄이 안 옴.

**가설 / 시도:**
1. (틀림) claude CLI cold start로 1-2분 걸리는 중 → ps로 확인했더니 `claude` 자식 process가 *없음*. /tmp의 PNG도 cleanup됨 → subprocess는 이미 끝났다는 뜻.
2. (정답에 근접) 사용자 셸의 `ANTHROPIC_API_KEY` env가 invalid (401). claude CLI가 그 env 우선시해서 401 받고 즉시 종료. 우리 `.output().await`는 종료한 child를 await했지만 frontend로 결과 못 보낸 지점은... (실제로 그 후 결과 잘 옴, 41초 첫 호출 시간이 함정. 사용자가 hang으로 오인.)

**원인:** 첫 vision 호출의 진짜 latency가 30-50초 수준이라 frontend "Analyzing…" 표시가 hang처럼 보임. + 셸 env의 `ANTHROPIC_API_KEY`가 invalid면 default로 그것 사용해서 401 발생 (별 원인이지만 같이 점검 필요).

**해결 + 학습:**
- Fix: `tokio::process::Command::env_remove("ANTHROPIC_API_KEY")`로 invalid 키 제거 → claude가 OAuth/subscription credential 사용.
- 교훈:
  - subprocess를 띄울 때 **부모 env를 그대로 상속한다고 가정 X**. 인증 관련 env는 명시적으로 제거하거나 set.
  - 사용자에게 "오래 걸린다"는 신호는 hang vs slow inference 구분 신호가 필요. dispatcher에 begin/ok/fail 로그를 박은 게 이번에 진단에 결정적이었다 — 모든 외부 호출에 같은 패턴.

---

## 2026-05-26 21:45 — `npm create tauri-app` rsync 머지가 `src-tauri/.gitignore` 삭제

**증상:** Phase 0.1 scaffold 후 cargo build가 `gen/schemas/*.json`을 트래킹할 candidate로 보임 (`git status`에 41개 staged).

**가설 / 시도:** rsync 명령 옵션 점검 → `--exclude='.gitignore'`이 *모든* 디렉토리의 .gitignore에 매치되는 것 확인.

**원인:** rsync `--exclude` 패턴은 path-suffix matching이 기본. 디렉토리 안 .gitignore까지 다 제외시킴.

**해결 + 학습:**
- Fix: rsync 후 `src-tauri/.gitignore` 수동 복원 + `git rm --cached -r src-tauri/gen/`.
- 교훈: rsync `--exclude`는 의외로 위험. 더 안전한 alternative는 `--exclude='/.gitignore'` (디렉토리 루트의 .gitignore만 매치) 또는 cp + 명시적 file list.

---

## 2026-05-26 21:30 — DNS sparse registry 실패 → cargo deps 다운로드 안 됨

**증상:** `cargo check`가 `Could not resolve host: index.crates.io` 에러로 fail. nslookup도 SERVFAIL.

**가설 / 시도:** `dscacheutil -q host -a name index.crates.io`는 정상 해석. mDNSResponder 캐시는 살아있는데 직접 DNS query는 SERVFAIL.

**원인:** 첫 query 후 DNS가 mDNSResponder 캐시에 prime되는 timing 문제. nslookup이 `/etc/resolv.conf` 직접 사용하는 server는 일시적으로 응답 안 함. 사용자 회사망 또는 ISP의 SERVFAIL 한 번 → cargo 즉시 fail.

**해결 + 학습:**
- Fix: `dscacheutil -q host -a name index.crates.io` 한 번 → cache prime → cargo retry 통과.
- 교훈: cargo의 "spurious network error" 메시지가 보이면 일시적. 첫 시도 fail해도 한 번 더 시도. 또는 DNS prime 트릭. 진짜 DNS 죽었으면 다른 명령도 fail해야 한다.

---

## 2026-05-26 22:50 — claude vision 호출이 매번 30-50초 (사용자 dogfooding 마찰)

**증상:** ⌥+Space → 텍스트 → Analyze → 41초 대기. 매번 비슷. 사용자가 "뒤지게 오래 걸리네"라 함.

**가설 / 시도:**
1. cold start만 그렇고 두 번째부터 빠를 거 — 부분 틀림. 두 번째도 35-40초.
2. (정답) PNG 사이즈가 압도적 원인. 3.3MB / 3456×2234 retina full-res는 claude vision tile 1568×1568를 여러 장으로 쪼개서 토큰/시간 폭증.

**원인:** claude vision API는 입력 이미지를 1568×1568 tile 단위로 처리. retina 풀해상도(3456×2234)는 4-6개 tile로 split → 토큰 ~5배 증가 + inference 시간 동시 증가. 추가로 Read tool 인코딩 시간도 사이즈에 비례.

**해결 + 학습:**
- Fix: `capture.rs`에서 캡처 직후 `MAX_DIMENSION=1568` 기준 Lanczos3 다운스케일. 큰 UI 요소(버튼/메뉴) 인식엔 영향 거의 없음, 작은 글자 약간 흐려짐.
- 예상 효과: 30-50초 → 15-25초.
- 교훈: vision API는 "이미지 크기 = 비용 + 시간"이 직접 비례. 클라이언트 측 다운스케일이 가장 큰 win. 모델 swap이나 inference 옵션 만지는 것보다 효과 크고 비용 0.
- (DECISIONS.md "Capture 해상도" 엔트리에서 trade-off 명시)

---

## 2026-05-26 23:10 — Groq vision 호스팅 현황 불명확 (해결됨)

**증상:** "현재 기준 최선" 답하려고 WebSearch 두 번 했는데 결과 모순.

**가설 / 시도:**
1. 첫 검색에서는 Groq blog (2024-09)에서 "Llama 3.2 Vision 출시" + Llama 3.2 11B Vision $0.18/M paid pricing 명시.
2. 두 번째 검색 ([Artificial Analysis Llama 3.2 11B Vision providers](https://artificialanalysis.ai/models/llama-3-2-instruct-11b-vision/providers))에서는 Amazon Bedrock / Azure / DeepInfra만 listed. Groq 없음.
3. **해결:** [Groq vision docs](https://console.groq.com/docs/vision) 공식 페이지 직접 fetch.

**원인:** Groq는 Llama 3.2 11B Vision은 deprecate, 현재 vision 모델은 **`meta-llama/llama-4-scout-17b-16e-instruct` 하나만** (preview 상태). Artificial Analysis가 측정 안 한 이유는 Groq의 vision lineup이 Llama 3.2 → Llama 4 Scout으로 교체됐기 때문.

**해결 + 학습:**
- Fix: GROQ_VISION_MODEL const가 우연히 정확한 값이었음. 변경 불필요.
- 새 fact:
  - 모델 상태: preview (experimental)
  - 한도: max 5 images/request, base64 4MB, 원본 20MB, 33 MP. 우리 다운스케일 후 ~1MB PNG라 OK.
  - 컨텍스트: 128K tokens, multilingual, JSON mode 지원.
  - 사이즈: 17B (Llama 3.2 11B보다 크고 더 정확할 가능성).
- 교훈: AI 모델 호스팅은 빠르게 변함. WebSearch가 모순일 때 vendor 공식 docs (이 케이스 `console.groq.com/docs/vision`) 직접 fetch가 30초로 진실 확정. 매번 첫 의문에 docs 가는 게 정답.

---

## 2026-05-27 17:01 — 오버레이가 다른 macOS Space에 떠 있음

**증상:** Space A에서 ScreenBridge dev 띄움 → Space B로 이동 → ⌥+Space → trigger panel은 안 보이거나 잘못 보이고, Analyze 결과 overlay가 Space A로 그려져 사용자가 못 봄.

**가설 / 시도:**
- macOS의 NSWindow는 *처음 생성된 Space*에 stick하는 게 기본 동작 (NSWindowCollectionBehaviorDefault).
- alwaysOnTop은 윈도우 level만 띄울 뿐 Space-following과 무관.

**원인:** Tauri webview window default가 `canJoinAllSpaces = false`. ScreenBridge 부팅 시 위치한 Space에 trigger/overlay 둘 다 묶임. 다른 Space로 가면 보이지 않음.

**해결 + 학습:**
- Fix: tauri.conf.json의 두 윈도우 모두에 `"visibleOnAllWorkspaces": true` 추가. Tauri가 NSWindow.collectionBehavior에 canJoinAllSpaces 매핑.
- 교훈: macOS의 단일 Space 가정은 menu-bar app 디자인에서 자주 깨짐. transparent/alwaysOnTop/fullscreen 셋업 시 Space 동작도 같이 점검.

---

## 2026-05-27 17:01 — Groq Llama 4 Scout 17B vision 실측: 76초 (예상 1-5초 대비)

**증상:** SB_DISPATCHER=groq 시도. 76,625ms (76초) 걸림. claude CLI 41초 대비 두 배. 좌표 인식 실패 (`coords=None`).

**가설 / 시도:**
- WebSearch에서 Groq "300-1000 tps / sub-200ms TTFT" 발견 → vision도 동일할 거라 추정.

**원인:** WebSearch 결과의 속도는 *텍스트* 모델 (Llama 3.3 70B 등) 기준. vision은 image encoder + token generation 두 단계라 다른 그림. Llama 4 Scout 17B는 preview 상태라 production 최적화 부족 가능. 또 우리 PNG 1MB의 base64 ~1.3MB 업로드 시간도 추가.

**해결 + 학습:**
- Fix 없음 — 측정 결과. Groq 옵션 dogfooding 후보로 폐기. DECISIONS 매트릭스에 실측값 갱신.
- 교훈: 텍스트 inference 벤치마크를 vision에 그대로 끌어다 추정하지 말 것. vision은 별도 측정. 사실 확인 안 됐으면 DECISIONS에 "검증 안 됨"으로 명시 — 이번엔 그렇게 박았는데 실측이 추정 깨뜨림.

---

## 2026-05-27 — Overlay가 "화면 가린다" — click-through 안 했던 게 원인

**증상:** 사용자가 ⌥+Space → Analyze → overlay 떠도 "화면 가린다" 불만 반복. transparent 정상이고 빨간 박스/bubble만 보이지만, *마우스 클릭이 overlay에 막혀* desktop의 진짜 버튼 못 누름. 사용자 입장 = "가린다".

**가설 / 시도:**
1. (틀림) macOSPrivateApi 미적용 → 흰색으로 가림. macOSPrivateApi:true config + features 둘 다 박았는데도 여전히 불만.
2. (틀림) fullscreen visible:false 무시 → setSize(1,1)로 회피했지만 결과 받으면 monitor 사이즈로 키움. 그게 가린 게 아니라 *클릭 차단이* 가린 거.
3. (정답) `setIgnoreCursorEvents(false)`로 overlay 활성 중 클릭 받음. 사용자가 desktop 작업 못 함 = "가려져 있음" 체감.

**원인:** Phase 5.2에서 "결과 보고 있는 동안 클릭으로 닫기 가능하게"라는 UX 가정 + 👍/👎 피드백 버튼 클릭. 그러나 PRODUCT.md 본질 = 안경 메타포 = *desktop 그대로 사용하면서 위에 떠 있는 가이드 보기*. 클릭 받는 순간 안경 아닌 가림막이 됨.

**해결 + 학습:**
- Fix: `setIgnoreCursorEvents(true)` 영구. 절대 false로 안 토글. 닫기는 ⌥+Space 다시 누르면 backend가 sb-trigger broadcast → overlay listen 핸들러가 close().
- 부작용: 👍/👎 피드백 버튼 마우스 클릭 불가 → v0.2에서 별도 micro-window로 옮김. recordFeedback IPC는 살아있음.
- 교훈: HUD/overlay 디자인에서 클릭 통과 여부는 product 본질과 직결. "닫기 편하게" 같은 UX 편의 갖다 붙이면 본질이 즉시 깨질 수 있음. PRODUCT.md 본질 직역 = setIgnoreCursorEvents(true).

---

## 2026-05-27 — Overlay 여전히 가림 — webview 자체 배경이 흰색이었다

**증상:** click-through 박은 후에도 사용자가 "여전히 여전히 여전히 가린다" 반복. transparent:true config + macOSPrivateApi + features 다 박았는데도.

**가설 / 시도:**
1. (틀림) macOSPrivateApi 미적용. backend 콘솔에 경고 없으므로 적용됨.
2. (틀림) Tauri transparent:true 옵션 미동작. setSize/show 후에도 webview는 transparent로 만들어졌음.
3. (정답) **`App.css`의 `:root { background-color: #f6f6f6; }`** 가 overlay webview에까지 적용되어 webview html element가 흰색을 그림. transparent는 *webview content가 transparent여야* 의미 있음. content가 흰색 칠하면 OS는 그 흰색을 그대로 표시.

**원인:** App.css는 trigger panel 디자인 위주로 작성됨. :root 자체에 배경색을 두면 *같은 React 번들을 로드하는 overlay webview*도 그 색을 받는다. Tauri의 두 윈도우는 같은 frontendDist를 로드 (`tauri.conf.json`의 단일 frontendDist 설정), label만 다름.

**해결 + 학습:**
- Fix:
  - `:root background: transparent` (배경 제거).
  - `html, body { background: transparent }` 명시.
  - `.trigger-panel { background: #f6f6f6 }`로 trigger panel만 색.
  - dark mode 분기도 같은 패턴.
- 교훈: multi-window Tauri에서 *transparent 윈도우 + 색 있는 윈도우*가 한 React 번들 안에 공존하면 :root/html/body에 색 두지 말 것. 색은 컴포넌트 root에만. PRODUCT.md "안경" 본질의 진짜 enabler는 CSS 작성 패턴.

---

## 2026-05-27 — Gemini가 free-form 텍스트로 응답, parse 2/3 실패

**증상:** SB_DISPATCHER=gemini 3회 호출 측정:
- 17:24:29 → 15s, raw_len=173, **모든 fields None**
- 17:38:43 → 8s, raw_len=593, **state ✓, next ✓, coords=[590,508,78,32] ✓**
- 18:46:06 → 9s, raw_len=174, **모든 fields None**

2/3 케이스 parse 실패. raw_len 173-174의 짧은 응답은 SYSTEM_PROMPT의 "JSON 외 텍스트 금지" 룰 무시.

**가설 / 시도:**
- (틀림) Gemini 모델 능력 부족. → 한 번은 정확히 좌표까지 잡음. 능력은 있음.
- (정답) Gemini는 `responseMimeType: "application/json"` + `responseSchema`로 *강제* JSON 출력 가능. SYSTEM_PROMPT 안 텍스트로만 "JSON으로 답해"는 비결정적 — Gemini가 free-form 텍스트로 답하면 parse_analysis가 fallback raw 표시.

**원인:** generationConfig에서 JSON 강제 옵션을 안 줬음. Anthropic은 SYSTEM_PROMPT의 강제력 강함 (sonnet은 99%+ JSON 출력), Gemini는 그것보다 느슨함 → 명시적 schema 필요.

**해결 + 학습:**
- Fix: GeminiDispatcher의 generationConfig에 `responseMimeType: "application/json"` + `responseSchema` (AnalysisResult 모양) 추가. screen_state/next_action/reasoning은 required, coordinates optional (모델이 좌표 못 잡는 케이스 OK).
- 교훈: vendor별 strict JSON 강제 메커니즘 다름.
  - Anthropic: SYSTEM_PROMPT 텍스트만으로 거의 항상 작동.
  - Gemini: generationConfig.responseSchema 명시.
  - Groq: json_object response_format 필요.
  - OpenAI: response_format json_schema.
  vendor swap 시 dispatcher 코드에 vendor-specific JSON enforcement 매번 명시. 한 번에 박을 것.

---

(다음 디버그는 여기에 append. 매 commit에 같이 들어가야 함. 사후 정리는 R8 위반.)

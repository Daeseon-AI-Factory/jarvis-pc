# DECISIONS

R9 (CLAUDE.md): 두 개 이상의 합리적 선택지가 있고 그중 하나를 골랐다면 즉시 5-파트 엔트리.

엔트리 형식:
```markdown
## YYYY-MM-DD — <결정 제목>
**선택지:** A / B / C 각각 한 줄.
**Trade-off:** 시간/돈/복잡도/유지보수/학습/리스크 등 어떤 축으로 평가했는지.
**선택:** A.
**근거:** 왜 A인지. "더 깔끔" 같은 모호한 근거 금지.
**되돌리기 비용:** 미래에 B로 swap하면 무엇이 깨지나. 어떤 commit/파일 만져야 하나.
```

---

## 2026-05-26 — Dispatcher: AnthropicDispatcher (API key) vs ClaudeCliDispatcher (CLI subprocess)

**선택지:**
- **A. AnthropicDispatcher** — `reqwest`로 `api.anthropic.com/v1/messages` 직접. `ANTHROPIC_API_KEY` 필요.
- **B. ClaudeCliDispatcher** — `tokio::process::Command::new("claude")` subprocess + `--print` 모드. 사용자의 Claude Code Pro/Max 구독 사용.
- C. ~~OpenAI / Gemini 등 다른 vendor~~ — PRODUCT.md "Anthropic API" 명시로 즉시 탈락.
- D. ~~로컬 vision (Ollama)~~ — v0.7 LLM Sovereignty 단계, 너무 일찍.

**Trade-off:**

| 축 | A (API key) | B (claude CLI) |
| --- | --- | --- |
| 호출당 시간 | 10-20초 | 15-40초 (Node 부팅 + Read tool overhead) |
| 호출당 비용 | ~$0.03 (vision sonnet) | $0 (구독 정액 안에서) |
| 월 비용 (10회/일) | ~$10-15 | $0 |
| 에러 가시성 | 401/403 명확 | subprocess silent fail 가능 |
| 인증 복잡도 | `.env` 한 줄 | subprocess env_remove 필요, keychain OAuth |
| 코드 단순도 | reqwest direct | subprocess + temp file + cleanup |
| SPEC 일치도 | PRODUCT.md "Anthropic API" 직접 | "Anthropic 자체"지만 CLI subprocess 회색 |
| dogfooding 사이클 영향 | 매번 -20초 빠름 | 매번 +20초 느림 |

**선택:** **B (현재 활성)**.

**근거:**
- v0.1은 dogfooding 검증 단계. 매일 5회 자발적 사용이 v0.2 진입 조건 → 월 ~150회 × $0.03 = $4.5. 적지만 user 입장에서 "추가 결제 등록"이라는 마찰이 사용 빈도를 줄일 수 있다. **습관 형성에 결제 마찰 = 치명적**.
- 사용자가 이미 Claude Code 구독 보유. sunk cost를 활용하는 게 합리적.
- 시간 trade-off (+20초)는 "이미지 다운스케일"로 일부 보상 가능 (v0.2 후보 1순위).
- B의 silent fail 리스크는 `dispatcher` target tracing 로그 (begin / ok / fail)로 완화 — 이번에 dispatcher.rs에 박은 패턴.

**되돌리기 비용:** 1줄. `lib.rs::analyze()`의 `dispatcher::ClaudeCliDispatcher::new()`를 `dispatcher::AnthropicDispatcher::new()?`로 치환만 하면 swap. 두 dispatcher 모두 `LLMDispatcher` trait 구현해 둠. `AnthropicDispatcher` 코드는 dispatcher.rs에 그대로 살아있음 (제거 X) — 미래 swap을 위한 단가.

**미해결 관심사:** B는 매 호출당 Node 부팅 (~1-2초)이 누적. v0.2에 `claude` CLI를 daemon 모드로 띄워두고 stdin pipe로 재사용하는 방안 검토 (`--input-format stream-json`).

---

## 2026-05-26 — 통합 테스트 위치: `screenbridge/tests/` vs `src-tauri/tests/`

**선택지:**
- **A. SPEC tree 그대로** — `screenbridge/tests/dispatcher_tests.rs` (프로젝트 루트).
- **B. Cargo 표준 위치** — `src-tauri/tests/dispatcher_tests.rs` (crate 루트).

**Trade-off:**

| 축 | A (SPEC 위치) | B (Cargo 표준) |
| --- | --- | --- |
| `cargo test --manifest-path src-tauri/Cargo.toml` 자동 발견 | ❌ 못 찾음 | ✅ |
| SPEC.md 디렉토리 트리 일치 | ✅ | ❌ (SPEC 위반 1건) |
| 추가 cargo config 필요 | yes (workspace 등 셋업) | no |

**선택:** **B (Cargo 표준)**.

**근거:** `cargo test`가 자동으로 찾는 위치 = `<crate>/tests/`. A는 workspace로 묶거나 별도 path 지정해야 발견 — 학습 비용 ↑ + maintenance 비용 ↑. SPEC tree 위반 1줄이지만 SPEC.md의 의도("integration test 한 묶음")는 지켜짐. SCRATCHPAD에 위반 1줄 기록.

**되돌리기 비용:** mid. `mv src-tauri/tests/dispatcher_tests.rs tests/` + Cargo.toml에 `[[test]] path = "../tests/dispatcher_tests.rs"` 추가. 그러나 별 이득 없으므로 되돌릴 일 없음.

---

## 2026-05-26 — 에러 enum: `thiserror` crate vs 손수 impl

**선택지:**
- **A. `thiserror`** — `#[derive(thiserror::Error)] enum FixtureError { #[error("io: {0}")] Io(#[from] std::io::Error), ... }`.
- **B. 손수 impl** — `enum FixtureError { Io(...) }` + `impl Display` + `impl Error` + `impl From<...>` 직접.

**Trade-off:**

| 축 | A | B |
| --- | --- | --- |
| 코드 라인 | 5-6줄 | 25-30줄 (boilerplate) |
| crate dep 추가 | +1 | 0 |
| 학습 가치 | 매크로 magic 뒤에 가려짐 | impl 자체가 학습 |

**선택:** **B (손수 impl)**.

**근거:** SPEC v0.1은 학습 dogfooding 우선. `thiserror`가 깔끔하긴 한데 매크로가 모든 trait impl을 자동 생성해서 "Display vs Error trait 차이"가 안 보임. v0.1 단계에선 boilerplate 한 번 손으로 써보는 게 미래 디버깅 자산. SPEC 룰 4 ("새 디렉토리/패키지 임의 생성 금지")의 정신과도 일치.

**되돌리기 비용:** 작음. 각 error enum에 `#[derive(thiserror::Error)]` 추가 + variant마다 `#[error("...")]` annotation. Cargo.toml에 `thiserror = "1"`. 30분.

---

## 2026-05-26 — Settings UI v0.1 scope: 풀 UI vs 트레이 한 항목

**선택지:**
- **A. 풀 Settings 윈도우** — 단축키 재바인딩 / 세션 wipe / 자동 시작 / 모델 선택.
- **B. 트레이 메뉴 "Open sessions folder" 한 항목만**.

**Trade-off:**

| 축 | A | B |
| --- | --- | --- |
| v0.1 작업 시간 | ~2-3시간 | 5분 |
| dialog plugin 의존 (wipe confirm) | 필요 | 불필요 |
| dogfooding 사이클 단축 효과 | 미미 (이 단계에서 단축키 바꿀 일 거의 없음) | OK |
| 사용자 입장 기능 누락 | 단축키 충돌 시 불편 | "필요해지면 직접 코드로" |

**선택:** **B**.

**근거:** "v0.1 = dogfooding 진입까지 최단거리"가 SPEC.md의 정신. 자기 자신이 사용자라 단축키 충돌 시 코드 한 줄 (`hotkey.rs::register_default`)에서 바꾸는 게 더 빠름. wipe는 Finder에서 직접 폴더 삭제. **풀 Settings UI는 v0.2의 진입 조건(주 5회 자발적 사용)을 만난 다음 합리**.

**되돌리기 비용:** small. `tauri-plugin-dialog` 추가 + Settings 윈도우 컴포넌트. SPEC.md Phase 6.3에 명시되어 있어 v0.2 첫 작업.

---

## 2026-05-26 — Overlay 윈도우 생성 시점: tauri.conf static vs WebviewWindowBuilder dynamic

**선택지:**
- **A. `tauri.conf.json`에 정적 정의** — `visible:false`로 부팅 시 생성, listen 등록도 부팅 시.
- **B. dynamic 생성** — 첫 analyze 결과 받았을 때 `WebviewWindowBuilder`로 생성.

**Trade-off:**

| 축 | A | B |
| --- | --- | --- |
| 부팅 비용 | webview 두 개 띄움 | trigger 하나 |
| 첫 결과 표시 latency | <100ms | 500ms+ (window 생성 + React mount + listen 등록) |
| 코드 복잡도 | 낮음 (선언적) | 중간 (state 관리, race condition 가능) |
| macOS visible/fullscreen 충돌 (TROUBLESHOOTING 21:55 참조) | 노출됨 | 회피 가능 |

**선택:** **A**.

**근거:** 첫 결과 표시 latency가 사용자 경험에 더 큰 영향. dynamic은 `analyze` 결과 받은 직후 윈도우 만들고 React mount까지 기다리면 추가 500ms+ — claude CLI 35초 호출 끝나고 한 번 더 0.5초 = 체감 더 답답. macOS 충돌은 1회성 디버그로 해결됨 (TROUBLESHOOTING 참조).

**되돌리기 비용:** mid-high. `tauri.conf.json` overlay 윈도우 제거 + `Overlay.tsx` listen 위치를 backend로 옮김 + dynamic creation 로직 추가. ~1시간.

---

## 2026-05-26 — Trigger Panel result 표시: panel 안 vs overlay 전환

**선택지:**
- **A. Trigger Panel 안에 result 표시** (Phase 4.2 상태).
- **B. Panel 닫고 별도 overlay에 표시** (Phase 5 상태, 현재).

**Trade-off:**

| 축 | A | B |
| --- | --- | --- |
| 좌표 박스 표시 | 어려움 (panel은 작은 윈도우) | 자연스러움 (fullscreen transparent) |
| 사용자 focus | panel 자체에 stuck | 화면 + 가이드 동시 |
| 코드 복잡도 | 낮음 | 중간 (두 윈도우 + 이벤트) |

**선택:** **B**.

**근거:** PRODUCT.md "AI 지시 ↔ 내 실제 화면 사이 번역 레이어"의 핵심 가치 = *실제 화면 위에 가이드 표시*. 좌표 박스는 fullscreen transparent overlay 없이는 불가. A는 핵심 가치 자체를 못 살림.

**되돌리기 비용:** 매우 높음 — 사실상 v0.1 자체를 못 만드는 결정. 본 결정은 *revertable이 아닌* SPEC.md Phase 5의 전제.

---

## 2026-05-26 — Capture 해상도: 원본 vs 1568×1568 cap vs 더 작게

**선택지:**
- **A. 원본 그대로** — Retina/HiDPI 풀해상도 (예: 3456×2234, 3.3MB PNG).
- **B. 1568×1568 cap (Lanczos3)** — claude vision tile base에 맞춤.
- C. 1024×1024 또는 더 작게.

**Trade-off:**

| 축 | A (원본) | B (1568 cap) | C (1024) |
| --- | --- | --- | --- |
| 호출당 latency | 30-50초 | 15-25초 | 12-20초 |
| 토큰/비용 (API key 모드 가정) | ~$0.04 | ~$0.015 | ~$0.008 |
| 작은 글자(<10px) 가독성 | best | good (Lanczos3로 보존) | poor |
| 큰 UI 요소 (버튼/메뉴/탭) 인식 | 동일 | 동일 | 동일 |
| 캡처 자체 시간 | <0.1s | +0.05s (resize) | +0.05s |
| 정확도 영향 | baseline | 미미 (대부분 큰 UI) | 글자 인식 실패 잦음 |

**선택:** **B (1568×1568 cap)**.

**근거:** claude vision tile이 1568×1568이라 그 이하면 1 tile로 들어가서 입력 토큰과 inference 시간 동시에 줄어듦. dogfooding 대상이 거의 항상 큰 UI 요소(클릭할 버튼, 선택할 메뉴 등) → 작은 글자 가독성 손실은 무시 가능. Lanczos3 필터로 다운스케일 품질도 보장.

**되돌리기 비용:** `capture.rs` `MAX_DIMENSION` 상수 1줄 변경 (1568 → 다른 값) 또는 다운스케일 분기 자체 제거. 10초.

**미해결 관심사:** 향후 폰트 작은 사이드바 메뉴 같은 케이스에서 가독성 떨어지면 multi-tile (원본 그대로) fallback 옵션 추가 검토. fixture로 비교 측정.

---

## 2026-05-26 — R8/R9 강제 강도: rule만 vs hook reminder vs pre-commit 차단

**선택지:**
- A. **CLAUDE.md rule만** — R8 R9 문서화. LLM이 매 작업 시 자체 적용.
- B. **+ .claude/settings.json hook** — Stop/PostToolUse 이벤트에 메시지 inject.
- **C. + .git/hooks/pre-commit** — 코드 변경 staged인데 TROUBLESHOOTING/DECISIONS 변경 없으면 commit 차단.

**Trade-off:**

| 축 | A | B | C (현재) |
| --- | --- | --- | --- |
| 강제력 | 약함 — LLM 무시 가능 | 중간 — reminder만 | 강함 — commit 자체 막힘 |
| 회피 비용 | 없음 | 없음 | `--no-verify` 의식적 |
| 셋업 시간 | 0분 | 5분 | 15분 |
| portable (다른 머신 clone) | yes (git tracked) | yes (.claude/ tracked) | **no** (.git/ untracked) |
| 오탐 (false positive) | n/a | 가벼움 | 단순 오타도 차단 → `--no-verify` 자주 |

**선택:** **C (A+B+C 다 활성)**.

**근거:** 사용자가 명시적으로 "확실히 hook"이라 요청. rule + reminder만으로는 이번 세션 후반에 *실제로* forgetting 발생 ("우리 트러블슈팅 기록되고 있나?" 사용자 직접 지적). commit 차단이 강제력 가장 큼. 단순 오타 commit은 `--no-verify` 우회 — 매번 의식하면 R8/R9 정신에 맞음.

**되돌리기 비용:** 두 파일 삭제. `.claude/settings.json`은 hook 부분만 제거하면 됨, `.git/hooks/pre-commit`은 파일 단위 삭제. 3분.

**미해결 관심사:**
- `.git/hooks/`는 git tracked X. 다른 환경에서 clone 시 hook 자동 설치 안 됨. scripts/setup-hooks.sh로 symlink 셋업 스크립트 추후 추가 후보 (SCRATCHPAD에 기록).
- pre-commit 차단이 너무 빈번하면 R8/R9 의미가 ritual로 변질될 수 있음 — 일주일 dogfooding 후 false positive 빈도 측정 후 룰 완화 여부 결정.

---

## 2026-05-26 — 시간 단축 옵션 전체 매트릭스 (vision dispatcher 후보)

**문제:** 현재 ClaudeCliDispatcher가 매 호출 30-50초 (다운스케일 후 15-25초 예상). dogfooding 사이클 답답. "무료 + 빠른" 옵션 시장 조사.

**옵션 (2026-05 시점 시장 fact-check):**

| # | 옵션 | 비용 | inference 속도 | vision 정확도 | 무료 한도 | dispatcher 신규? | SPEC 룰 6 위반 |
| -- | --- | --- | --- | --- | --- | --- | --- |
| A | **claude CLI subprocess** (현재) | $0 (Pro/Max 구독 활용) | 15-25초 (다운스케일 후 추정) | ★★★★★ sonnet-4-6 | 구독 정액 안 | 기존 | 회색 (Anthropic 자체) |
| B | **API key + sonnet-4-6** | ~$0.02/호출, 월 $10 (10회/일) | 10-15초 (추정) | ★★★★★ | 신규 가입 무료 크레딧만 | 기존 (한 줄 swap) | 위반 X |
| C | **Gemini 2.5 Flash API** | $0 | 5-15초 (Google TPU, 추정) | ★★★★ Flash | **250 RPD**, 10 RPM, 250K TPM | 신규 GeminiDispatcher | **위반** |
| C′ | Gemini 2.5 Flash-Lite | $0 | C와 비슷 | ★★★ Flash-Lite | **1,000 RPD**, 15 RPM | 같음 | **위반** |
| D | **Groq + Llama 3.2 11B Vision** | $0 | **1-5초** (LPU, sub-200ms TTFT + 300-1000 tps) | ★★★ 11B 모델 | **1,000 RPD**, 30 RPM | 신규 GroqDispatcher | **위반** |
| E | **Ollama 로컬 Llama 3.2 11B Vision** | $0 | 추정 15-40초 (M3 Pro 텍스트 8B = 28-35 tok/s; vision 11B는 더 느림, 정확 데이터 없음) | ★★★ | 무제한 (RAM 한정) | 신규 OllamaDispatcher | 위반 + Ollama 셋업 |

**검증된 fact (sources):**
- Gemini free tier RPM/RPD: ai.google.dev/gemini-api/docs/rate-limits
- Groq Llama 3.2 Vision available: groq.com/blog (2024-09 출시), Llama 3.2 11B Vision $0.18/1M paid tier
- Groq free tier: console.groq.com/docs/rate-limits — 30 RPM / 1000 RPD / 6K TPM
- Groq LPU latency: console.groq.com/docs (sub-200ms TTFT, 300-1000 tps)
- Apple Silicon Llama text inference: 28-35 tok/s on M2 Air for 3B, 28-35 tok/s on M3 Pro for 8B (llama.cpp/Metal)

**검증 안 된/추정:**
- Llama 3.2 11B Vision (Ollama 로컬)의 정확한 tok/s — vision 모델은 텍스트보다 느림이 일반적, 그러나 specific Apple Silicon benchmark는 검색 결과에서 못 찾음. 5-15 tok/s 추정.
- C/D의 한국어 instruction 처리 정확도 — fixture 측정 없이는 모름. v0.1 dogfooding 자체가 측정대.

**Trade-off 축:**

| 축 | 가중치 | 평가 메모 |
| --- | --- | --- |
| 호출당 시간 (사용자 체감) | **높음** | 매일 5+회 사용에 사이클 길면 안 씀 |
| 무료성 | **높음** | 사용자 명시 |
| 정확도 | **중간** | dogfooding은 "버튼 어디" 수준이면 충분. fixture로 측정 필요 |
| dispatcher 구현 시간 | 낮음 | trait 추상화 덕에 일관 |
| SPEC 룰 6 위반 | 낮음 | 룰 의도("Anthropic 묶음")는 v0.1 구조 안정화 목적. dogfooding 마찰 해소가 더 우선 |
| 신뢰성 | 중간 | 무료 RPD 도달 시 503/quota → fallback chain 필요 |

**선택 후보:**
- 1순위 추천 **D (Groq + Llama 3.2 11B Vision)**: 압도적 속도 (1-5초). 무료 1000 RPD. dogfooding 가속 효과 최대. 정확도 손실은 fixture로 측정 후 결정.
- 2순위 **C (Gemini Flash)**: Google 인프라 안정성. 250-1000 RPD. vision multimodal 자연스러움.
- 3순위 **A 유지 + B fallback**: claude CLI 그대로 + 무료 한도 안 들면 API key로 fallback (월 $10). 정확도 ★★★★★ 보존.

**미선택 + 근거:**
- E (Ollama 로컬): 인터넷 끊겨도 동작 매력적지만 (a) 모델 다운로드 4-12GB (b) vision 11B의 M Mac latency 미검증 (c) Ollama 셋업이 v0.1 외부 의존. v0.7 LLM Sovereignty 단계 본격 후보.
- D′ (Groq + Llama 4 Scout/Maverick): vision 지원 정보 검색에서 명확 X. Llama 3.2 11B Vision만 vision 명확.

**미해결:**
- 한국어 vision 지시 처리 정확도 측정 (A vs C vs D). fixture 3개로 동일 input 보내 next_action 결과 비교. v0.1 dogfooding 진입 전 1회 측정 권장.
- Fallback chain 설계: D 무료 한도 도달 → C로 fallback → A로 fallback. dispatcher trait의 `Vec<Box<dyn LLMDispatcher>>`로 chain 구현 가능 (1-2시간).

**선택:** **사용자 결정 대기** (Groq vs Gemini vs claude 그대로).

**2026-05-27 실측 갱신:**

| dispatcher | 측정 시간 | 좌표 인식 | 정확도 (1회 측정) | 비고 |
| --- | --- | --- | --- | --- |
| claude CLI (Pro 구독) | 41초 (첫 호출) | ✓ `[334,155,370,220]` | sonnet 답변 길고 정확 | TROUBLESHOOTING 22:50 |
| Groq Llama 4 Scout 17B (preview) | 76초 | ✗ `coords=None` | "Cancel 버튼 클릭" — 좌표 없으면 박스 X | 예상 1-5초 vs 실측 76초. preview vision 최적화 부족 |
| **Gemini 2.5 Flash** (responseSchema 없음) | **7-15초** (3회 평균 ~10초) | 1/3만 ✓ `[590,508,78,32]` | 한 번은 정확, 두 번은 free-form 텍스트 → parse 실패 | responseSchema 추가하면 안정화 예상 |
| **Gemini 2.5 Flash + responseSchema (현재)** | 측정 중 | 측정 중 | 강제 JSON 출력 | TROUBLESHOOTING 2026-05-27 (Gemini free-form fix) |

**최종 후보:**
- 1순위 **Gemini 2.5 Flash (responseSchema 강제)** — 속도 7-15초 + 좌표 인식 가능 + 무료 250 RPD. sonnet 41초의 1/3 시간. 안경 메타포 UX 가능 수준.
- 2순위 claude CLI Pro 구독 — 정확도 최고, 속도 답답.
- 후보 폐기 Groq — 속도 + 정확도 둘 다 약함.

**되돌리기 비용:** 어느 옵션도 dispatcher trait 그대로 활용. 새 Dispatcher struct 하나 추가하고 lib.rs::analyze에서 한 줄 swap. 기존 ClaudeCliDispatcher/AnthropicDispatcher는 보존. 1-2시간 구현 + fixture 측정 30분.

---

## 2026-05-26 — Dispatcher swap 메커니즘: env var vs config file vs build feature

**선택지:**
- **A. `SB_DISPATCHER` env var** — `SB_DISPATCHER=groq npm run tauri dev` 식. 4개 분기 (claude/groq/gemini/anthropic).
- B. `~/.screenbridge/config.toml` 설정 파일 — 한 번 설정 후 영구.
- C. `cargo build --features=groq` — 컴파일 타임 분기.

**Trade-off:**

| 축 | A (env var) | B (config file) | C (cargo feature) |
| --- | --- | --- | --- |
| 측정 사이클 (4개 dispatcher 비교) | 빠름 (env만 바꿈) | 중간 (파일 편집) | 매번 재컴파일 |
| 런타임 swap | 가능 (dev 재시작) | 가능 | 불가 (rebuild) |
| 코드 변경 | 분기 한 곳 (lib.rs) | config 모듈 추가 | features 셋업 + cfg |
| 사용자 UX | 익숙 (셸 env) | 한 번 설정 후 까먹음 | 어색 |

**선택:** **A**.

**근거:** 지금 단계 = dispatcher 정확도/속도 비교. 매번 다른 옵션 한 번씩 돌려보는 게 워크플로. env var가 가장 빠른 측정 사이클. v0.2에 default를 결정하면 그때 B(config) 추가 검토.

**되돌리기 비용:** 작음. lib.rs::analyze match arm 4개를 default 한 줄로 줄이고 다른 dispatcher 코드는 보존. 30분.

---

## 2026-05-26 — Groq vision 모델 const: 가설값 + 사용자 검증

**선택지:**
- A. WebSearch 결과 기반 모델 ID 박음 (Llama 3.2 11B Vision).
- **B. 가설값 const + 사용자가 console.groq.com/docs/models 직접 확인 후 교체**.
- C. 동적 fetch — Groq의 `/v1/models` endpoint로 vision 지원 모델 자동 발견.

**Trade-off:**

| 축 | A | B | C |
| --- | --- | --- | --- |
| 할루시네이션 리스크 | 높음 (Groq 호스팅 상태 검색 모순) | 낮음 (사용자 검증) | 낮음 |
| 사용자 마찰 | 0 | 1번 console 방문 | 0 |
| 코드 복잡도 | 낮음 | 낮음 | 중간 (추가 API 호출) |
| 시점 의존성 (모델 deprecate) | 높음 | 낮음 (재방문) | 낮음 |

**선택:** **B**.

**근거:** TROUBLESHOOTING 23:10에 기록한 모순 — 검색 결과로 단정 못 함. 가설값을 const로 두고 사용자가 console 직접 확인하면 (a) 현재 시점 정확한 모델 ID 박을 수 있고 (b) Groq vision 호스팅 자체 확인되며 (c) 측정 사이클은 그대로 빠름. 할루시네이션 방지가 사용자 명시 요구.

**되돌리기 비용:** 작음. const 한 줄 교체. 또는 v0.2에서 C(동적 fetch)로 swap.

---

## 2026-05-27 — Overlay 상호작용: 클릭 받기 vs 진짜 HUD (click-through)

**선택지:**
- A. **클릭 받기 모드** (이전 디자인) — `setIgnoreCursorEvents(false)`. overlay 안에서 클릭으로 닫기, 👍/👎 버튼 클릭 가능. 단 desktop 작업 차단됨.
- **B. 진짜 HUD (click-through)** — `setIgnoreCursorEvents(true)` 영구. 마우스가 overlay 통과 → desktop의 진짜 버튼 클릭 가능. 닫기는 키보드 (⌥+Space 토글).
- C. 작은 bubble 윈도우 (fullscreen X, 우하단 320×200 fixed) — 좌표 박스 표시 불가.

**Trade-off:**

| 축 | A (클릭 받기) | B (HUD click-through, 현재) | C (작은 bubble) |
| --- | --- | --- | --- |
| 빨간 박스 좌표 표시 | ✓ | **✓** | ✗ |
| desktop 정상 사용 | ✗ (차단) | **✓** (진짜 안경) | ✓ |
| 닫기 UX | 클릭 / ESC | ⌥+Space 토글 | 자동 / 단축키 |
| 👍/👎 피드백 클릭 | ✓ | ✗ (통과되어 못 누름) | ✓ |
| PRODUCT.md "안경" 메타포 | 부분 | **정확 일치** | 부분 |

**선택:** **B**.

**근거:** 사용자가 명시적으로 "안경 낀 듯이"라는 product vision 재확인. PRODUCT.md "AI 지시 ↔ 실제 화면 사이 번역 레이어"의 본질 = 사용자가 *실제 desktop을 그대로 사용하면서* 위에 떠 있는 가이드 본다. A는 desktop 작업 차단해서 본질 깨짐 — overlay 떠있는 동안 사용자가 진짜 New Project 버튼 클릭조차 못 함. B가 product 본질과 정확히 일치.

피드백 버튼 click 손실은 v0.2에서 별도 micro-window (작은 always-on-top 클릭 받기 윈도우)로 분리해서 복원. recordFeedback IPC는 ipc.ts에 그대로 살아있음.

**되돌리기 비용:** 매우 작음. Overlay.tsx의 setIgnoreCursorEvents(true) → 결과 받으면 false로 다시 토글하는 줄 두 줄로 회귀. 5분.

**미해결 관심사:**
- 피드백 (👍/👎) 어떻게 복원? v0.2에서 micro-window 또는 menu-bar tray 항목.
- ⌥+Space 토글: trigger panel 열려있을 때 누르면 overlay close (이미 동작), overlay 떠있을 때 누르면 close 단독 (이번 fix). 동시에 둘 다 떠있는 케이스는 없으니 단순 토글로 충분.

---

## 2026-05-27 — 99% 정확도 architecture: OCR vs DOM extension vs Accessibility API

**문제:** Gemini Flash + DPR 변환 후 박스 정확도 ~70% (±50-100px). 사용자 명시: "99% 정확성 필요. 모델 스왑은 없다. 속도는 지금으로 유지." → **LLM에게 픽셀 좌표 추정 시키지 말고 deterministic source에서 좌표 얻기**. LLM은 element identification만.

**선택지:**

| # | 옵션 | source | 커버리지 | 추정 정확도 | 추가 시간 |
| -- | --- | --- | --- | --- | --- |
| A | **macOS Vision framework OCR** | 화면의 모든 text + bbox | 모든 앱 (text-based UI) | 95-99% (icon-only 제외) | 6-8h |
| B | Chrome extension + DOM | active tab의 DOM tree | 브라우저만 | 99-100% | 4-6h |
| C | macOS Accessibility (AXUIElement) | OS의 UI tree | 모든 앱 (Electron/sandboxed 약함) | 85-95% | 8-12h |
| D | 셋 다 hybrid + fallback chain | 위 셋 ∪ | 거의 100% | 18-24h |

**Trade-off (각 축):**

| 축 | A (OCR) | B (Chrome) | C (Accessibility) | D (Hybrid) |
| --- | --- | --- | --- | --- |
| dogfooding case 커버리지 | universal (브라우저 + native) | 브라우저만 (사용자 ~80% 케이스) | 모든 앱 (단 일부 약함) | 거의 모든 case |
| 정확도 | 95-99% text-based, icon 약함 | 99-100% (DOM은 truth) | 85-95% (앱별 노출도 다름) | 99%+ |
| 속도 (총 latency) | +0.5s (OCR) → ~10s | -1s (LLM이 더 적게 보냄) → ~9s | +0.2s (AXUIElement) → ~10s | 위 셋 중 가장 짧은 source 선택 |
| 권한 | Screen Recording (이미 있음) | Chrome extension install | Accessibility (신규, 강한 권한) | 모두 |
| 구현 비용 | 6-8h | 4-6h | 8-12h | 18-24h |
| 라이브러리 | cocoa-foundation/objc2 + Vision framework | manifest v3, WebSocket | objc2 + AXUIElement | 위 둘 |
| 사용자 친화도 | 0 (투명) | install 한 번 | 권한 다이얼로그 | 위 모두 |
| Cross-platform 호환 | macOS 한정 | Chrome 한정 | macOS 한정 | macOS 한정 |
| SPEC.md 위치 | (없음, v0.1 추가) | v0.3 명시 | v0.5+ 시사 (LLM Sovereignty 아닌 별도) | (없음) |

**선택:** **A (macOS Vision framework OCR + LLM element matching)**.

**근거:**
- **universal**: 사용자가 매일 쓰는 케이스 = 브라우저 (80%) + 데스크톱 앱 (20%, Slack/Mail/Finder/터미널 등). A는 둘 다. B는 브라우저만.
- **dogfooding 진입까지 ROI 최대**: 6-8h 안에 정확도 70% → 95-99%로 점프. PRODUCT.md "주 5회 자발적 사용" gate를 진짜 통과할 정확도.
- **속도 영향 미미**: macOS Vision framework 자체가 native + GPU 가속. OCR ~300-500ms 추가, 총 ~10초 sweet spot 유지.
- **권한 추가 없음**: Screen Recording은 이미 부여됨. Accessibility(C)는 사용자에게 신규 권한 다이얼로그 — 마찰 ↑.
- **LLM이 일을 잘하도록**: 픽셀 추정 같은 약점에서 빠지고 element identification에 집중. 정확도 자체 ↑.
- **B(Chrome extension)는 v0.3으로 보강** — SPEC.md 명시 trajectory와 일치. A 다음에 B 추가하면 브라우저 case는 100% 정확 + native fallback 유지.
- **C(Accessibility)는 v0.5+** — Electron/sandboxed 앱 약함 + 권한 마찰. B 추가 후에도 부족하면 그때.

**미선택 + 근거:**
- B (Chrome extension only): 브라우저만 — Slack/Mail/Finder 등 일상 작업 못 커버. v0.3에 같이 추가.
- C (Accessibility only): 권한 + 앱별 노출도 ↓ + 구현 비용 ↑. ROI 가장 나쁨.
- D (hybrid): 좋지만 v0.1 단계에 비용 너무 큼. A → B → C 순차 진화.

**Architecture 디테일 (A 채택 시):**
```
사용자 화면 캡처
   ├─→ 다운스케일 PNG (Gemini Flash 비전 입력)
   └─→ macOS Vision framework
            VNRecognizeTextRequest → list of (text, bbox)
   ↓ LLM에 같이 보냄:
      - PNG (시각 컨텍스트)
      - OCR text list 부착 in user_text
      - SYSTEM_PROMPT: "next_action에 클릭할 element의 정확한 visible text 명시. 좌표는 backend가 list에서 매칭"
   ↓
LLM 응답 (Gemini schema 강제):
   { next_action: "...", target_text: "Create API Key",
     coordinate_hint: [원래 picture px], ... }
   ↓
backend element-text fuzzy match (OCR list)
   ↓
정확한 coords (OCR bbox)
   ↓
Overlay box: 99% 정확
```

**되돌리기 비용:**
- 부분 rollback (OCR 비활성, LLM 좌표만): lib.rs::analyze에서 OCR 호출 조건부 skip. SB_DISPATCHER=gemini 같은 env로 토글. 5분.
- 완전 rollback (OCR 모듈 제거): src-tauri/src/ocr.rs 삭제 + Cargo crates 제거. 30분.

**미해결 / 향후:**
- **icon-only 버튼** (text 없는 X 버튼, 햄버거 메뉴 등): OCR 매칭 실패 → LLM 좌표 fallback (현재 동작 그대로). v0.2 후보: 자주 쓰는 icon library 등록.
- **fuzzy matching 정확도**: "Create API Key" vs "Create API key" 대소문자, 공백, "API Key 생성" 한국어 번역 — backend matcher 일관성. levenshtein 또는 substring 우선.
- **macOS Vision framework Rust crate 선택**: `cidre`, `objc2-vision`, 또는 직접 cocoa interop. 다음 단계에서 fact-check.

**SPEC 위반 기록:**
- 룰 4 ("새 디렉토리/패키지 임의 생성 금지, SPEC 구조 엄수"): `src-tauri/src/ocr.rs` 새 모듈 추가 — SPEC 트리에 없음. SCRATCHPAD에 위반 1줄 기록 + dogfooding 측정 결과 (정확도 70%) 기반 정당화.
- 룰 6 ("Anthropic API 외 외부 LLM 라이브러리 v0.1엔 추가 금지"): OCR은 LLM 아님 — 위반 X.

---

## 2026-05-27 — OCR 구현 방식: macocr subprocess vs objc2-vision direct

**선택지:**
- **A. macocr CLI subprocess** — `cargo install macocr` (v0.4.7, 2026-02-16). Rust binary, CLI/HTTP 모드. ClaudeCliDispatcher와 동일 subprocess 패턴.
- B. objc2-vision direct binding — Rust에서 cocoa interop 직접.

**Trade-off:**

| 축 | A (subprocess) | B (direct) |
| --- | --- | --- |
| 구현 시간 | 2-3h | 8-10h |
| 사용자 setup | `cargo install macocr` 1번 | 없음 |
| Cold start | ~50-100ms 추가 | 0 |
| Cargo deps | 0 | 5-6 (objc2, objc2-vision, objc2-foundation, core-graphics 등) |
| 일관성 | 기존 ClaudeCliDispatcher subprocess와 같은 패턴 | 새로운 interop |
| 미래 deprecation 위험 | macocr crate가 unmaintained 시 | objc2 API churn |

**선택:** **A (macocr subprocess)**.

**근거:**
- 시간 단축이 dogfooding 진입까지 critical. 2-3h vs 8-10h.
- macocr가 우리가 원하는 정확한 output JSON 형식 (`ocr_boxes[{x,y,w,h,text}]`) — 추가 wrapping 불필요.
- subprocess 패턴 ClaudeCliDispatcher와 일관 — 디버그 노하우 재사용.
- v0.2에 source 추상화 (trait OcrProvider)로 objc2-vision swap 가능. 결정 reversible.

**되돌리기 비용:** ocr.rs 한 모듈 + macocr 라이브러리 호출만 objc2-vision 코드로 교체. ~10h.

---

## 2026-05-27 — Multi-monitor: cursor monitor capture (SPEC "단일 Space" 깸)

**선택지:**
- A. 기존 — primary monitor 또는 monitors[0]만. SPEC 룰 따름.
- **B. Cursor 위치 monitor 캡처 + overlay 그 monitor에**. PRODUCT.md "단일 Space" 룰 깬다.
- C. 모든 monitor 캡처 + 합성 (panorama) → LLM 한 번 호출.
- D. 모든 monitor 각각 LLM 호출 → 결과 합치기.

**Trade-off:**

| 축 | A (primary only) | B (cursor monitor, 채택) | C (panorama) | D (multi-call) |
| --- | --- | --- | --- | --- |
| 사용자가 본 화면 정확히 캡처 | ✗ multi-monitor에선 fail | ✓ 항상 | ✓ | ✓ |
| 구현 비용 | 0 | 1-2h (core-graphics + Monitor::from_point) | 4-6h (panorama 합성 + 좌표 매핑) | 2-3h × N |
| 비용 (API 호출 수) | 1 | 1 | 1 | N |
| 좌표 계산 복잡도 | 단순 | 단순 (monitor 단위 local) | 복잡 (panorama 좌표 → individual monitor 매핑) | 단순 N개 |

**선택:** **B**.

**근거:**
- dogfooding signal — 사용자가 daily multi-monitor. SPEC "단일 Space" 룰이 깨졌음을 실측이 증명. 룰보다 실측 우선.
- ⌥+Space 누르는 시점에 *cursor가 어느 monitor에 있냐*가 "사용자가 본 화면"의 deterministic proxy. macOS NSEvent.mouseLocation을 core-graphics로 받음. ~10줄 코드.
- C/D는 사용자 케이스 (한 monitor 작업, 다른 monitor reference) 분석에 과한 비용. cursor 단일 monitor가 95% 케이스 커버.
- A 유지 시 multi-monitor 사용자 = 항상 잘못된 monitor 캡처 = dogfooding 불가.

**되돌리기 비용:** 작음 — capture.rs의 cursor monitor 선택 분기를 primary fallback으로 회귀. `core-graphics` crate 제거.

**SPEC 위반 기록:**
- PRODUCT.md "v0.1: 단일 macOS Space만 지원". 단일 monitor 함의. multi-monitor capture는 그것 깬 거 — dogfooding measurement 기반 룰 update.

**미해결:**
- Cursor가 monitor 경계에 있을 때 from_point의 동작 (return 한 쪽 monitor).
- Trigger panel은 여전히 home monitor에 stick. ⌥+Space 누른 monitor가 home과 다르면 panel 안 보임. 별도 fix 필요 (panel도 cursor monitor로 이동).

---

## 2026-05-27 — **STACK SWAP: Tauri → Swift macOS native** (가장 큰 결정)

**문제:** dogfooding 진입까지 16개 layer를 trial-and-error로 발견 (`TROUBLESHOOTING.md` + `PROJECT_TIMELINE.md` 매트릭스). 사용자 명시: "냉정하게 사용성 최대화".

**선택지:**
- A. **Tauri 그대로 + 점진적 native (objc2)** — sunk cost 보존, 추가 feature마다 또 layer 발견 가능성.
- **B. Swift native rewrite** ← 채택. Apple SDK 표준 패턴. macOS HUD app의 textbook architecture.
- C. Tauri WebView (UI) + Rust objc2 (모든 native) hybrid — A의 다른 모양.

**Trade-off:**

| 축 | A (Tauri 유지) | B (Swift rewrite, 채택) |
| --- | --- | --- |
| dogfooding 진입까지 시간 | ~3-5일 (남은 layer 박기) | 1-2주 (rewrite) |
| 좌표 정확도 | OCR + LLM matching ~95-99% | AXUIElement ~99-100% |
| 새 feature 개발 속도 | Tauri 추상화 우회 매번 | SDK 표준 한 줄 |
| Multi-monitor / Spaces 통합 | 부분 (visibleOnAllWorkspaces 등 한정) | `.collectionBehavior` 모든 옵션 |
| Accessibility API | objc2 raw binding 매번 | SwiftUI에서 SDK 표준 |
| Cross-platform 옵션 | 보존 | **포기 (macOS only)** |
| sunk cost | 0 (모두 살림) | ~3000줄 Tauri 코드 (학습 가치는 보존) |

**선택:** **B**.

**근거:**
- ScreenBridge product type = macOS-native HUD overlay. Apple SDK가 textbook pattern 정해놓은 카테고리.
- 사용자 우선 가치 = "냉정하게 사용성 최대화". cross-platform이나 학습 보존이 아님.
- 발견한 16 layer 중 *모두* macOS native SDK에서 1-3줄로 해결. 16 commit이 16줄로 압축.
- 미래 v0.5+ "Spaces multi-desktop" / v0.7+ "LLM Sovereignty (로컬 모델)" trajectory에서 native interop 깊이 사용 어쩌피 — 일찍 swap이 더 깔끔.
- 학습 자산 (`TROUBLESHOOTING.md`, `DECISIONS.md`) = stack-independent. Swift에서도 같은 함정 피함.

**되돌리기 비용:**
- `git tag v0.1-tauri-attempt` + `git branch tauri-archive` (둘 다 push 완료) — 영구 백업.
- 1줄: `git checkout tauri-archive` → Tauri 코드 복원.
- 단 dogfooding 시점에 사용성 비교는 직접 측정 필요.

**미해결:**
- PRODUCT.md / SPEC.md의 "Tauri 2.0만 사용" 룰 (절대 규칙 5). 룰 자체 update 필요 → `CLAUDE.md` 룰 5 update.
- SPEC.md Phase 매트릭스의 Tauri-specific Phase (0.1 scaffold, 3.x system integration, capability 등)는 Swift에선 다른 형태. SPEC update 또는 새 SPEC_SWIFT.md.
- v0.1 "주 5회 자발적 사용" gate는 stack 무관 유지.

---

## 2026-05-29 — AnalysisResult: `raw`는 Codable에서 분리 vs CodingKeys 포함

**선택지:**
- **A. `raw`를 CodingKeys에서 제외** — `init(from:)`/`encode(to:)` custom, raw는 stored property로 dispatcher가 `withRaw(_:)` builder로 후채움. struct shape ↔ LLM JSON 1:1.
- **B. `raw`를 CodingKeys 포함 + `decodeIfPresent` default ""** — Codable 자동 syntheses 가까움. LLM 응답엔 raw 키가 없으므로 매번 빈 문자열 받음.
- C. ~~`raw` 필드 제거 + dispatcher가 별도 `AnalysisEnvelope { result, raw }` wrapper~~ — call site에서 두 객체 다루기 번거롭고 sessions/logs 저장 시 raw가 result에 동반되어야 함.

**Trade-off:**

| 축 | A (분리) | B (포함) |
| --- | --- | --- |
| Codable boilerplate | init(from:)+encode(to:) custom 필요 (~25줄) | 자동 syntheses (0줄) |
| LLM JSON 매핑 명확도 | 1:1 — LLM이 안 주는 필드는 schema 밖 | raw가 schema에 있는데 LLM이 안 줌 → 의미 모호 |
| dispatcher 호출 코드 | `result.withRaw(raw)` 한 줄 | decoder만으로 raw="" 통과 |
| 후처리 명시성 | builder로 raw 주입이 visible | 외부에서 raw 채우려면 새 struct 만들어 copy |
| OCR fallback 정신 일치도 | dispatcher가 raw 직접 관리 → 디버깅 시 dispatcher만 보면 됨 | raw가 어디서 채워지는지 흐릿 |

**선택:** **A**.

**근거:**
- AnalysisResult의 Codable shape은 **LLM의 응답 schema 그 자체**다. Phase 2.3 Gemini dispatcher가 `responseSchema`를 강제할 때 struct가 schema와 1:1이어야 한다. raw는 LLM이 채우는 게 아니라 dispatcher가 채우는 메타데이터 → schema 밖.
- 25줄 boilerplate < schema 매핑의 명확성. + Phase 2.3에서 `JSONEncoder().encode(AnalysisResult)` 결과를 그대로 `responseSchema` keys 검증에 쓸 수 있음. raw가 포함되면 그 검증 깨짐.

**되돌리기 비용:** 1 파일 — `AnalysisResult.swift`의 CodingKeys에 `raw` 추가 + custom init/encode 제거 + `withRaw(_:)` 호출 callsite 제거 (Phase 2.3 미작성이라 현재 0 callsite). 5분.

**미해결:** Phase 2.3에서 `responseSchema`를 AnalysisResult shape에서 자동 derive할지 (Mirror) vs 수동 mirror할지 — 현재는 수동 예상 (Swift Codable에 schema 추출 표준 없음).

---

## 2026-05-29 — CodingKeys: snake_case 명시 vs `convertFromSnakeCase` 전략

**선택지:**
- **A. CodingKeys에 `case screenState = "screen_state"` 직접 명시** — 키 매핑이 한 곳에 visible.
- **B. `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`** — 자동 변환, struct에 enum 없어도 됨.
- C. ~~Swift macro `@CodingKey(.snakeCase)`~~ — A의 syntactic sugar + dependency 추가 (CLAUDE.md 절대규칙: dep 0 우선).

**Trade-off:**

| 축 | A (명시) | B (자동 변환) |
| --- | --- | --- |
| 키 가시성 | grep "screen_state" → 한 줄 | grep 안 잡힘 — implicit |
| Encode/Decode 대칭 | 양방향 OK | encoder도 `convertToSnakeCase` 별도 set 필요 — 비대칭 위험 |
| LLM JSON spec 변경 시 디버그 | `target_text` 검색 → AnalysisResult.swift 즉시 | LLM 키와 코드 식별자 직접 연결 없음 |

**선택:** **A**.

**근거:**
- LLM dispatcher 응답 schema는 *vendor 계약*에 가까움. 키 매핑은 grep 가능한 한 곳 (CodingKeys)에 명시되어야 schema audit 가능.
- Phase 2.3 GeminiDispatcher가 `responseSchema`를 보낼 때 key가 snake_case여야 → encoding/decoding 양방향에서 같은 키 명시가 안전.
- Tauri 시절 LLM 응답 키 변경 (`step_text` → `next_action`) 디버그 경험: grep 가능한 명시 키가 결정적이었음.

**되돌리기 비용:** 1 파일. CodingKeys enum 제거 + `keyDecodingStrategy=.convertFromSnakeCase` set in dispatcher. 5분.

---

## 2026-05-29 — .env parser: 직접 구현 vs DotEnv 라이브러리

**선택지:**
- **A. 직접 구현** — `Env.parse(_:)` ~25줄. KEY=VALUE / `#` 주석 / quote / `export` prefix.
- B. SPM dotenv package (`SwiftDotenv`, `DotEnv` 등). 기능 풍부 (variable interpolation, override 우선순위 등).

**Trade-off:** dep 0 (cold start, 빌드 시간, audit 표면, supply-chain) vs 풍부한 기능.

**선택:** **A**.

**근거:**
- CLAUDE.md 절대규칙 6 ("외부 LLM 라이브러리 v0.1 추가 금지")의 정신 = 보수적 dep 관리. 25줄 parser << dep 1개 + transitive supply-chain audit.
- v0.1 단일 사용자 단계. variable interpolation/override 같은 풍부 기능 불필요 — 우리 use case = API key 한 줄 로드.
- `.env`가 표준 형식이라 직접 구현이 brittle 우려 없음. 8 unit tests로 형식 커버 (KEY=VALUE / 주석 / 빈 줄 / quote / export / whitespace / invalid line / nonexistent key).

**되돌리기 비용:** 1 파일 — `Env.swift` 삭제 + `Package.swift` dep 추가 + import 한 줄. 10분.

---

## 2026-05-29 — SYSTEM_PROMPT: 한국어 강제 (v0.1) + ✗/✓ 페어 직역

**선택지:**
- **A. 한국어 SYSTEM_PROMPT** — `next_action` 등 모든 응답 한국어.
- B. 영어 SYSTEM_PROMPT — "LLM이 영어를 더 잘 따른다" 통설.
- C. 동적 i18n — locale에 따라 자동 swap.

**Trade-off:** 톤 자연스러움 (v0.1 user = 한국어 native) + bubble copy 직결 vs 영어 LLM 성능 + 미래 i18n.

**선택:** **A**.

**근거:**
- 사용자(v0.1 dogfooding) = 한국어 native + 본질이 "AI 추상 지시를 *친근하게* 설명". 영어 응답을 frontend에서 한국어로 번역하면 톤이 부자연 + latency.
- Gemini 2.5 Flash는 한국어를 충분히 잘 따름 (Vision OCR `ko-KR` 정식 지원).
- ✗/✓ 페어 (Tauri Layer 16 학습) 직역: `"auth button"` ✗ vs `"Sign in"` ✓, `"the create button"` (군더더기) ✗ vs `"Create API Key"` ✓. visible text 룰을 *예시로 강제 학습*.
- v0.2+에서 영어/일본어 사용자 발생 시 `Prompts.systemPrompt(for: Locale)` factory로 확장. 현재 dep 0.

**되돌리기 비용:** `Prompts.systemPrompt` 상수 한 곳. 또는 factory function 한 개 추가. 10분.

---

## 2026-05-29 — NSLog → os.Logger 전체 swap

**선택지:**
- A. `NSLog` 유지 — Foundation, 의존 0. 단 Console.app에서 mute, 사용자 stream 어려움.
- **B. `os.Logger` (`OSLog`)** — Apple unified logging. Console.app + `log stream` + Xcode console + privacy 명시 + os_signpost 자동.
- C. `print` — stdout 직접. Console.app/system log 안 들어감, signpost 없음.

**Trade-off:** dev/사용자 가시성 + log level + privacy 명시 vs 추가 import 한 줄.

**선택:** **B**.

**근거:**
- 사용자 좌절 신호 (memory `user-pain-dev-tool-friction`, 2026-05-29 verbatim): "로그 볼줄도 모르는게 어렵네". 해결 = log이 *Console.app + 별도 terminal `log stream`* 모두에서 동시 가시.
- `log stream --predicate 'subsystem == "com.screenbridge.app"' --info` 한 명령으로 별도 terminal에서 ScreenBridge log만 stream. dev 일관 흐름.
- privacy 명시 (`.public`/`.private`/`.sensitive`) — 향후 API 키 등 누설 위험 차단. NSLog은 무차별.
- `os_signpost` 자동 — Phase 4.2에서 dispatcher latency 측정에 활용 가능.

**되돌리기 비용:** 각 file의 `Log.X.info(...)` → `NSLog(...)` 치환 + `import OSLog` 제거 + `Logging.swift` 삭제. 4 files, 10분.

---

## 2026-05-29 — Gemini API: URLSession 직접 vs Google SDK

**선택지:**
- **A. URLSession async/await 직접** — Foundation only, dep 0.
- B. Google Gemini SDK (공식 `google-genai-swift` 또는 community wrapper) — Codable Request/Response 자동, retry 자동.
- C. `swift-openapi-generator` from API spec — vendor-neutral.

**Trade-off:** dep 0 (cold start, audit, supply-chain lock-in) + 100% control vs 풍부한 wrapper.

**선택:** **A**.

**근거:**
- CLAUDE.md 절대규칙 6 ("외부 LLM 라이브러리 v0.1 추가 금지") + Phase 2.2 `.env` parser와 같은 정신.
- URLSession + Codable + JSONEncoder/Decoder 만으로 ~250줄에 완성 (request + response + retry + schema enum). vendor SDK 추가 시 audit 표면 + transitive deps.
- Vendor swap 시 `LLMDispatcher` protocol 통해 — wrapper 라이브러리에 lock-in 안 걸림. Anthropic, Claude CLI subprocess 등 추가는 protocol 새 implementation만.

**되돌리기 비용:** `Package.swift`에 dep + import — 그러나 `LLMDispatcher` protocol 통해 swap. 30분.

---

## 2026-05-29 — 권한 startup trigger (eager) vs Phase 3 capture 호출 시점 (lazy)

**선택지:**
- **A. AppDelegate `applicationDidFinishLaunching` startup에서 `CGRequestScreenCaptureAccess()` 호출**.
- B. `ScreenCapture.captureCursorScreen()` 호출 시점에 lazy로 권한 체크 + 거부 시 throw.
- C. Sheet/modal로 명시 onboarding flow.

**Trade-off:** dev 흐름 (silent fail 회피) + UX timing (첫 launch 다이얼로그 vs 첫 trigger) + 코드 복잡도.

**선택:** **A**.

**근거:**
- Sweep workflow advice: 권한 다이얼로그는 Phase 3.1 capture 작성 도중 *silent fail*로 디버그 시간 잃는 함정 회피. 명시적으로 startup에서 trigger.
- 사용자 좌절 흐름 일관 (memory `user-pain-dev-tool-friction`): 첫 launch에 권한 한 번 → 이후 안 물음. lazy는 첫 ⌥Space 누른 시점에 다이얼로그 → 사용자 흐름 끊김.
- macOS 권한 다이얼로그 거부 시 *재출현 안 됨* — `Permissions.openScreenRecordingSettings()` URL + relaunch 안내 필요. lazy는 거부 시점이 첫 trigger라 onboarding 어색.
- Accessibility는 별도 — Phase 6.2 (AXUIElement) 시점에 lazy로. 이유: v0.1엔 안 쓰니까 사용자 burden 미루기.

**되돌리기 비용:** AppDelegate의 `Task { @MainActor in ... Permissions.requestScreenRecording() ... }` 블록 제거 + ScreenCapture.captureCursorScreen 안에 lazy 체크 + onboarding sheet 추가. 30분.

---

## 2026-05-29 — Screen capture: ScreenCaptureKit vs CGDisplayCreateImage (legacy)

**선택지:**
- **A. ScreenCaptureKit** (`SCShareableContent` + `SCContentFilter` + `SCScreenshotManager.captureImage`) — macOS 12.3+. 권한 명시 (Screen Recording TCC).
- B. `CGDisplayCreateImage(displayID)` — Quartz Display Services 1.0부터. macOS 14에서 *deprecated*.
- C. `CGWindowListCreateImage` — window-based, display 전체 캡처 가능. macOS 15+ deprecated 예정.

**Trade-off:** API 안정성 + Apple 권장 + 미래 vs legacy 익숙도.

**선택:** **A**.

**근거:**
- B/C는 macOS 14+에서 *deprecated*. Apple은 ScreenCaptureKit 강제 방향.
- ScreenCaptureKit은 `SCStreamConfiguration`으로 pixel format / scale / showsCursor / captureResolution 명시 제어. Phase 3.1의 4-layer 좌표 변환에 정확한 physical pixel 필요 → 정밀 제어 필수.
- `SCScreenshotManager.captureImage` (macOS 14+) 단일 호출로 one-shot 가능 — SCStream 비디오 시작 없이.
- Permissions TCC 흐름이 명시적 — 사용자 좌절 흐름과 일관 (다이얼로그 startup trigger 가능).

**되돌리기 비용:** `ScreenCapture.swift`의 SCShareableContent/SCContentFilter/SCStreamConfiguration/SCScreenshotManager → `CGDisplayCreateImage(displayID)` 한 줄. 단 macOS 14+에서 deprecation warning. 20분.

---

## 2026-05-29 — DisplayGeometry: globalAppKitRect helper 강제 (raw CGRect setFrame 차단)

**배경:** Phase 3.1 commit 후 adversarial verify workflow가 `logicalRectFromSentBox`가 screen-local top-left만 반환하고 `screenFrame.origin`을 미반영하는 BLOCKER 발견. Phase 5 HUD code가 raw CGRect 받아 `NSWindow.setFrame` 직접 호출하면 외부 monitor에서 primary로 떨어짐 (Tauri Layer 9 재발 100% 보장).

**선택지:**
- **A. `globalAppKitRect(fromLocalTopLeft:) -> NSRect` 명시 helper** — caller에 doc comment + helper 강제. screen.origin add + y flip 한 곳.
- B. typed wrapper `struct ScreenLocalTopLeftRect { let rect: CGRect }` — compile-time 차단.
- C. 그대로 — Phase 5 HUD code가 직접 산수.

**Trade-off:** type safety 강도 vs boilerplate vs Phase 5 산수 burden.

**선택:** **A**.

**근거:**
- C는 verify workflow가 BLOCKER로 잡음 — reject.
- B는 가장 안전하지만 typed wrapper 추가 ~25줄 + 모든 caller에 `.rect` unwrap. v0.1엔 boilerplate cost > 안전성. Phase 5 HUD가 *유일한 호출자*라 wrapper의 marginal value 낮음.
- A는 doc comment + helper 강제 + 3 unit tests (primary / 외부 monitor x=1440 / vertical stack origin.y=900)로 lock. PR review 단계 `setFrame(geom.logicalRectFromSentBox(box)!)` 패턴 차단 가능.

**되돌리기 비용:** `globalAppKitRect(fromLocalTopLeft:)` 제거 + Phase 5 HUD가 직접 origin add + y flip. 단 verify lesson 잊으면 Tauri Layer 9 재발 — 위험 비용 크다. 1 파일 변경.

---

## 2026-05-29 — HUD overlay architecture: single screen-wide window + SwiftUI 내 박스 vs N box-sized window

**선택지:**
- **A. Single `HUDOverlayWindow` per screen, screen 전체 frame + SwiftUI 안에 박스/bubble**.
- B. Box-sized NSWindow per annotation (작은 frame만, 박스 크기) + multi-window 관리.
- C. NSWindow 1개를 모든 monitor에 setFrame (union frame) — multi-monitor 단일 window.

**Trade-off:**

| 축 | A (screen-wide single) | B (box-sized N) | C (union all monitors) |
| --- | --- | --- | --- |
| multi-monitor | cursor screen 1 window | 박스마다 정확 좌표 | union frame 복잡 + 비효율 |
| click-through | screen 전체 (사용자 desktop 클릭 OK) | 박스 위에만 | union 전체 |
| 좌표 변환 | `window.setFrame(screen.frame)` raw OK + SwiftUI 좌표 그대로 | 박스마다 `globalAppKitRect` 강제 | union frame 산수 |
| bubble overflow | SwiftUI clamping | window reposition | union 안에서 |
| 자기 캡처 (Phase 4.2) | sharingType=.none 1개 | sharingType=.none N개 (관리) | 1개 |
| 향후 다중 박스 + bubble + 화살표 | SwiftUI layout 자연 | N 새 window 생성 | SwiftUI layout |

**선택:** **A**.

**근거:**
- v0.1은 *한 화면 = 한 동작* (Prompts SYSTEM_PROMPT 본질) — 박스 1개. 단 향후 multi-step에 박스 + bubble + 화살표 component 추가 시 A의 SwiftUI 안 layout이 자연스러움.
- B는 외부 monitor 시 박스마다 `globalAppKitRect(fromLocalTopLeft:)` 강제 — verify fix lesson 적용 자리지만 일관성 cost > 단순성.
- C는 union frame이 multi-monitor 다른 backingScaleFactor 시 복잡 + Tauri 시절 모든 monitor 덮기 시도 (multi-monitor 함정 가중) 회피 정신과 충돌.
- A의 `screen.frame`은 global AppKit이라 raw `setFrame` 안전 — verify fix lesson "raw 금지"는 partial conversion (`logicalRectFromSentBox` 결과)에만 적용, `screen.frame`은 별개. `HUDController.present` 주석에 명시.

**되돌리기 비용:** `HUDOverlayWindow`/`HUDController` 변경. B로 가면 박스마다 NSWindow + `globalAppKitRect` 호출. 1일.

---

## 2026-05-29 — ScreenCaptureService protocol 도입 (테스트 가능성 vs static enum 직접)

**선택지:**
- A. AnalyzeCoordinator가 `ScreenCapture.captureCursorScreen()` enum static func 직접 호출. test에서 mock 불가.
- **B. `ScreenCaptureService` protocol + `LiveScreenCapture` struct wrapper** — test에서 `MockCapture` 주입.
- C. Closure injection (`capture: @Sendable () async throws -> (Data, DisplayGeometry)`) — protocol 없이.

**Trade-off:** test 가능성 vs boilerplate vs 일관성.

**선택:** **B**.

**근거:**
- AnalyzeCoordinator의 핵심 흐름 (capture → dispatcher → AnalyzeStage 반환)을 unit test로 lock해야 — Phase 5.x/6.x에서 stream 모드 등 확장 시 회귀 차단.
- `LLMDispatcher` protocol 이미 있음 — capture도 같은 패턴 (protocol + Live impl)이 일관.
- C는 closure type 길음 + 일관성 깨짐. dependency 2개 (capture + dispatcher) 다른 패턴이면 코드 읽기 어려움.
- B의 boilerplate (~15줄)는 4 unit tests (happy path / dispatcher 에러 / capture permission denied / 중복 reject)로 가치 충분.

**되돌리기 비용:** AnalyzeCoordinator init에서 `capture` 파라미터 제거 + `ScreenCapture.captureCursorScreen` 직접 호출. test에서 capture mock 부분 삭제. 30분.

---

## 2026-05-29 — v0.1 임시: `coordinates` fallback only → 반드시 강제 (OCR 도입 전 가교)

**배경**: Phase 4.2 첫 사용자 dogfooding — LLM (Gemini 2.5 Flash)이 SYSTEM_PROMPT 룰 잘 따름 → `coordinates` 키 생략 (target_text만 반환, backend OCR 매칭 기대). 그러나 Phase 6.1 OCR matcher 미작성 → 모든 분석이 "정확한 위치를 못 찾았어요" 에러. 사용자 dogfooding 흐름 끊김.

**선택지:**
- **A. v0.1 임시: `coordinates` 항상 강제** — SYSTEM_PROMPT 룰 swap + `responseSchema.required`에 추가. LLM 추정 좌표 ~70% 정확도지만 *뭐든 시각화*.
- B. 즉시 Phase 6.1 — Vision OCR + ElementMatcher. deterministic 99%.

**Trade-off:** dogfooding 흐름 유지 vs 본질 정확도 (99%).

**선택:** **A** (v0.1 한정) → 그 다음 Phase 6.1 (정답).

**근거:**
- 본질 ("99% 좌표는 OCR이 source") 일관 — *v0.1 한정 명시*. Phase 6.1 commit 시점에 다시 swap.
- v0.1 dogfooding 가치: latency 실측 (Gemini 2.4s total — 가설 8-15s 대비 ~5배 빠름) / target_text 정확도 / HUD UX 검증 — 모두 OCR 정확도와 *독립적*. 임시 fix가 그 검증 가능하게 함.
- A의 boilerplate: SYSTEM_PROMPT 2 곳 + responseSchema `required` 1 곳 + tests 2 곳 = ~10줄. 5분.
- B는 1-2시간 — 사용자 dogfooding 흐름 끊김 동안 latency / target_text / UX 자료 못 얻음.

**되돌리기 비용:** SYSTEM_PROMPT coordinates 룰 섹션 + 응답 형식 메시지 + responseSchema `required`에서 `coordinates` 제거 + tests 2개 업데이트. Phase 6.1 commit 직전 5분.

**미해결 / lock-in 위험**: LLM 추정 좌표 ~70% — 사용자가 빗나간 박스 봄. dogfooding 자료로 OCR 가치 명확화. Phase 6.1 commit 시점에 *반드시* swap 다시 — 안 그러면 본질 ("99% 좌표는 OCR이 source") 자기 모순 (verify workflow가 잡을 패턴).

**[2026-05-29 갱신, Phase 6.1 commit] lock-in 약속 지킴**: OCR matcher 도입 후 SYSTEM_PROMPT "fallback only" 정책 + responseSchema required에서 `coordinates` 제거. 본질 정확히 일관 — verify workflow가 자기 모순 잡을 패턴 사전 차단.

---

## 2026-05-29 — ElementMatcher fuzzy threshold 0.7 (Levenshtein similarity)

**선택지:**
- A. threshold 0.6 — 관대 (false positive 위험: 무관 텍스트도 박스 그어짐).
- **B. threshold 0.7** — 균형 (Levenshtein "CLAUDE.md" ↔ "CLAUDE.txt" = 0.78 → 매칭, "CLAUDE.md" ↔ "totally different" = 0.0~0.1 → 거부).
- C. threshold 0.85 — 엄격 (소문자/whitespace 차이만 허용, OCR 인식 오류 1-2자 허용 X).
- D. confidence-weighted (OCR confidence × Levenshtein) — 미래 옵션.

**Trade-off:** 매칭 성공률 vs false positive 위험 vs OCR 인식 오류 허용도.

**선택:** **B (0.7)**.

**근거:**
- LLM이 `target_text`를 visible text 정확히 줘서 (실측 "CLAUDE.md" 정확) — 표면 정확도 높음.
- 그러나 OCR이 1-2자 잘못 인식 가능 (`l`/`1`, `O`/`0`, 한글 점 등) → 엄격하면 매칭 fail.
- substring 매칭 (case-insensitive)이 *우선* — 0.7 fuzzy는 fallback. 대부분 substring 단계에서 hit.
- Phase 6.1 첫 dogfooding 후 *false positive 빈도* / *false negative 빈도* 측정. 갱신 가능.

**되돌리기 비용:** `ElementMatcher.defaultThreshold` 상수 한 줄. unit test `customThreshold` 추가/제거. 5분.

**미해결:** dogfooding 자료 (false positive vs false negative 비율) 후 갱신. 또는 D (confidence-weighted) 도입.

**[2026-05-29 갱신, Phase 6.1 verify fix]** Adversarial verify workflow가 짧은 텍스트 false positive HIGH 발견 (`"Save"` vs `"Same"` 0.75 통과). Length-aware threshold 추가:
- `defaultThreshold = 0.7` (긴 텍스트, ≥7자)
- `shortTextThreshold = 0.85` (≤6자 auto-tighten — caller가 default threshold 사용 시만)
- 명시 caller threshold는 그대로 (test용 escape hatch)

short text false positive 차단 (wrong-box 위험 가장 큼 — bubble UX 직격).

---

## 2026-05-29 — ElementMatcher 정규화 강화 (NFC + punctuation strip + tiebreaker)

**배경:** Phase 6.1 adversarial verify workflow가 한국어 NFC/NFD silent mismatch, punctuation 처리 부재, tiebreaker 미정의 발견.

**3가지 변경:**

1. **NFC Unicode normalization** — Swift String `==`은 canonical equivalent로 같지만 codepoint 비교 (`unicodeScalars`, Levenshtein 내부)는 다를 수 있음. `normalize()` 시작에 `.precomposedStringWithCanonicalMapping` 명시. 한국어/일본어/베트남어 conjoining script defensive.

2. **Punctuation strip** — `CharacterSet.punctuationCharacters` 제거. OCR error의 가장 흔한 source. `"CLAUDE.md"` vs `"CLAUDE md"` (점 drop) → 매칭. `"CLAUDE.md"` vs `"CLAUDE.txt"` strip 후에도 `"md"` vs `"txt"` Levenshtein 차이로 정확히 reject (다른 파일).

3. **Confidence tiebreaker** — 같은 길이 substring 매칭 시 `OCRBox.confidence` 높은 박스 우선. 동일 button text가 dialog/menubar 양쪽에 있을 때 비결정적 동작 차단.

**Trade-off vs cost:**
- Punctuation strip이 `.md` vs `.txt` 정확한 reject 유지하면서 — OCR error는 흡수.
- Tiebreaker 추가 코드 (~5줄). Confidence는 OCRBox에 이미 있음 — extra cost 없음.
- NFC normalize는 Swift 자동 처리 외 defensive — extra cost ~1줄.

**되돌리기 비용:** `normalize()` 3줄 변경 + substring sort 변경. 10분. 단 한국어 매칭 silent fail / wrong-box false positive 위험 재발.

**미해결:** OCR latency 측정 (실측), confidence-weighted matching (현재는 fail-over 우선만).

---

## 2026-05-30 — Spatial fusion: LLM coords hint + OCR proximity filter (wrong-box 차단)

**배경**: Phase 6.1 dogfooding이 wrong-box false positive 큰 issue 드러냄. 사용자가 "Save"/"Slack" 시도 시 — 화면 *여러 영역*에 같은 텍스트 있어 OCR substring 매칭이 *틀린 영역* 박스 잡음 (예: 어시스턴트 응답의 "slack 못 찾았어"에 박스 뜸, 사용자는 Dock의 Slack 아이콘 기대). 번역기 본질 신뢰 직격.

**선택지:**
- **A. LLM coordinates를 *영역 hint*로 활용 + OCR proximity filter** — LLM ~70% 정확하지만 *대략적 영역*은 맞음 (Dock vs window content 구분 가능). 30분 fix.
- B. 사용자 `LastTriggerContext.cursor`를 hint로 — proximity radius로 cursor 근처 박스만. 단 cursor가 panel 영역 → 부정확.
- C. Phase 6.2 AXUIElement로 Window/Dock/AXRole 구분 (~1-2시간).
- D. SYSTEM_PROMPT에 "사용자 cursor 근처 우선" 명시 (LLM이 추가 처리).
- E. OCR confidence 기준 정렬 — 단 모든 박스 confidence 비슷 (Vision .accurate).

**Trade-off:** 즉시 가능 vs 정확도 vs 사용자 intent 표현.

**선택:** **A** 즉시 + 향후 C (Phase 6.2) hybrid.

**근거:**
- A는 *기존 LLM coordinates* 활용 — Phase 4.2 fix에서 강제 → Phase 6.1에서 fallback only 되돌림. 단 LLM이 줄 *수* 있음. SYSTEM_PROMPT 갱신으로 hint 권장 명시 — 강제 X (본질 일관: OCR이 source).
- C는 정확하지만 시간. A는 30분. 둘 *결합*도 자연 (AX 후보 + LLM hint).
- B는 cursor가 ⌥+Space 시점 위치 — 사용자가 *이미 안 곳*을 기억하는 게 아니라 *AI가 시킨 곳* 찾는 거라 hint로 부적합. (사용자 intent: "Slack 어디?"는 Dock 영역 — cursor와 무관.)
- D는 SYSTEM_PROMPT 부담 ↑. A의 hint가 더 단순.

**구현:**
- `Prompts.swift` coordinates 룰: "fallback only" → "fallback OR 위치 hint 권장" 추가. 강제 X.
- `ElementMatcher.match`에 `llmHintRect: CGRect? = nil`, `proximityRadius: CGFloat = 200pt` 파라미터.
- hint 있으면 중심 ±200pt 안 박스만 candidate. 0개면 full fallback (LLM hint 부정확 안전망).
- `AnalyzeCoordinator`가 `result.coordinates` → CGRect → ElementMatcher hint 전달.

**되돌리기 비용:** `ElementMatcher.match` signature backward compatible (llmHintRect=nil 기존 동작). AnalyzeCoordinator에서 hint nil 전달. 5분.

**미해결:**
- LLM이 coords 안 주면 proximity 안 작동. → 향후 cursor 기반 또는 (LLM 응답에 "영역 키워드" 추가 — `header`/`dock`/`sidebar` 같은).
- `proximityRadius` 200pt 튜닝 자료 dogfooding 후 갱신 (1568px sent image에서 ~12.7% 너비).

---

## 2026-05-30 — Phase 6.2 AX matcher architecture: MatchCandidate unified type + OCR/AX 합집합

**배경**: Phase 6.1 spatial fusion이 wrong-box를 차단했지만 — **icon-only UI (Dock 아이콘, iOS-style 버튼)에 OCR이 텍스트 자체 못 잡음**. 사용자 "Slack 어디?" → Dock의 Slack 아이콘 = OCR 결과 0. AXUIElement는 모든 clickable element의 AXTitle/AXDescription/AXPosition/AXSize 메타데이터 — *icon-only도 deterministic*. 사용자가 직접 이 gap 통찰.

**선택지:**
- **A. MatchCandidate unified type + OCR/AX 합집합** ← 선택
- B. ElementMatcher에 `matchAX` 별도 method — OCR 매칭 fail 후 AX 시도 (2-step fallback)
- C. AX만 사용 (OCR 폐기) — text-rich UI 손해
- D. OCR-AX bridge로 AX 결과를 OCR 좌표계로 변환 — 복잡

**Trade-off:** 코드 일관성 vs OCR/AX 우선순위 명확성 vs 매칭 알고리즘 단순성.

**선택:** **A**.

**근거:**
- A는 *한 알고리즘*에서 OCR + AX 같이 비교 — best match 직접 선택. text-rich UI에서 OCR이 specific match, icon-only에서 AX가 유일 candidate — 둘 다 같은 통합 candidate pool에 넣어 single best 선택.
- substring tiebreaker에 *AX 우선* 박음 — 동일 길이 매칭 시 AX (deterministic 좌표) 선택. icon-only는 OCR이 못 잡으니 AX가 유일 후보 자연.
- B는 2-step — wrong-box 가능성 더 큼 (OCR이 잘못 잡으면 AX 안 봄).
- C는 OCR의 visible text 정확도 손해. Phase 6.1 OCR architecture 폐기.
- D는 좌표 변환 복잡 — *합집합*보다 burden 큼.

**구현:**
- `MatchCandidate` struct: `text` + `rectInLogicalPt` (이미 변환된 좌표) + `confidence` + `source: .ocr | .ax(role)`.
- `ElementMatcher.match([MatchCandidate])` overload — proximity / substring / fuzzy 동일 알고리즘.
- 기존 `match([OCRBox], geometry)` backward compatible — 내부에서 `MatchCandidate`로 변환.
- AnalyzeCoordinator: `async let dispatcher + OCR + AX` 3개 병렬. OCR/AX 실패 fatal X — graceful fallback (LLM coords).

**되돌리기 비용:** `MatchCandidate` 제거 + ElementMatcher overload 제거 + AnalyzeCoordinator OCR-only로 revert. 단 icon-only UI gap 재발 (Slack 못 풀음). 1시간.

**미해결:**
- AX query latency 실측 — `runningApplications` × tree walk (depth 8). 큰 앱 (Cursor 등 Electron) tree 크면 1-2s 가능. timeout 추가 검토.
- Electron 앱 (Slack 자체, Discord, VS Code 등)의 AX tree가 *비어있을 수 있음* — 그 앱 안 element 못 잡음. Phase 6.3+에서 vendor-specific fallback (예: Electron의 chrome accessibility flag) 검토.
- `clickableRoles` 화이트리스트 — Dock 외 잘 안 잡는 element (예: SwiftUI native button) 있을 수 있음. dogfooding 후 갱신.

---

## 2026-05-30 — Latency speedup: image 1568 → 1024 (정확도 vs 속도 trade-off, ship mode)

**Pragmatic ship mode** (memory `pragmatic-ship-mode`) — 완벽 X, 속도 우선.

**선택지:**
- A. **maxDimension 1024** ← 선택. Gemini latency ~30%↓ + OCR ~30%↓ + 토큰 ~40%↓. 작은 텍스트 정확도 약간↓.
- B. maxDimension 1568 유지 — 정확도 최우선. 단 latency 3-10s 사용자 burden.
- C. maxDimension 768 — 가장 빠름. 단 정확도 큰 손해.

**선택:** A.

**근거:**
- 어머님 use case는 *큰 button/menu/Dock 아이콘* — 작은 텍스트 손해 OK.
- 사용자 burden (3-10s 기다림) > 정확도 marginal 손해.
- dogfooding 자료 후 갱신 가능 — 1024 부족하면 1280 등.

**되돌리기 비용:** `ScreenCapture.maxDimension` 상수 한 줄. 1분.

**미해결:** dogfooding 후 정확도 실측 — 작은 텍스트 (사이드바 파일명 / 메뉴 단축키 등) 손해 정도. 1280 또는 1408 검토.

---

## 2026-05-30 — Preferred AX role from instruction (Chrome Dock vs MenuBar 모호함 차단)

**배경**: 사용자 "chrome 켜서 네이버 들어가래" → LLM target_text="Chrome" (정상). 단 Chrome이 *이미 켜져있어* AX에 두 곳: `AXDockItem` (Dock) + `AXMenuBarItem` (메뉴바의 Chrome 메뉴). 동일 길이 substring 매칭 → tiebreaker 비결정적 → 잘못 menubar.

**선택지:**
- **A. instruction에서 role 추론 (backend-only)** — "켜기/열기" → AXDockItem, "설정/메뉴" → AXMenuItem. SYSTEM_PROMPT 변경 X.
- B. AnalysisResult.targetRole: String? 추가 → LLM이 role 명시 + schema 확장. 큰 변경.
- C. SYSTEM_PROMPT에 role examples 추가 (LLM이 학습) — 강도 약함.

**선택:** **A**. Pragmatic ship mode — 작은 backend fix.

**근거:**
- B는 schema 변경 (큰 work, ship mode 위반).
- C는 LLM에 의존 — 안 따를 수도.
- A는 keyword inference, deterministic, instant.

**구현:**
- `ElementMatcher.inferPreferredRole(from instruction)` — "켜기/열기/실행/launch" → "AXDockItem", "설정/메뉴/quit" → "AXMenuItem".
- `match` signature에 `preferredRole: String?` 추가. 동일 길이 substring tiebreaker에 *최우선*.
- `AnalyzeCoordinator`가 inference → match 전달.

**되돌리기 비용:** 3 lines remove. 1분.

**미해결:** keyword list dogfooding 후 확장 (한국어 + 영어 + 일본어). Phase 7+에 LLM이 직접 target_role 줄 수도.

**[2026-05-30 갱신, prefer-only mode]**: 처음 fix는 *sort tiebreaker*만 — 약해서 wrong-box (Chrome menubar) 그대로. Strengthen: **preferred role 매칭 *있으면* 그것만 candidates** (다른 role 무시). 매칭 0개면 fallback to all (log notice). + AXService에 *Dock items 명시 log* — 디버그 시 "Chrome 진짜 Dock에 있나" 즉시 확인.

**[2026-05-30 갱신, multi-target overlay]**: Vision LLM 정확도 ~80-90% 본질 한계 인정 → *95% effective accuracy* 도달은 **사용자가 1초만에 1번/2번 선택**. `matchTop(maxResults: 2)` distinct candidates (rect 거리 > 50pt). HUD에 primary 빨강 + alternative 회색 dashed + 번호 라벨. *User-in-the-loop 차별* — 빅테크 agent (자동 클릭 위험) 대비 안전.

**[2026-05-30 갱신, LLM target_role hint]**: keyword inference ("켜기" → AXDockItem)는 모호 instruction ("Slack 새 메시지") 못 잡음. responseSchema에 `target_role` optional 추가 → LLM이 화면 context + instruction 보고 *직접 명시* (`AXDockItem`/`AXMenuItem`/`AXButton` 등). matcher 우선순위: **LLM target_role > keyword inference > 없음**. SYSTEM_PROMPT에 macOS Accessibility role 10종 + 예시. *되돌리기 비용*: schema 1줄 + matcher 4줄 — 30분 revert.

**[2026-05-30 갱신, dispatcher pre-warm]**: 첫 analyze 호출이 cold TLS handshake + DNS resolve로 ~1-2s 추가. LLMDispatcher protocol에 `func prewarm() async` (default noop) — GeminiDispatcher만 override (model list GET, cost 0). 앱 launch 시 Task.detached 호출 → 사용자가 ⌥+Space 누를 때 connection pool warm. *되돌리기 비용*: protocol 4줄 + AppDelegate 5줄 — 5분 revert. 추적 — Latency playbook Trick C 실측.

## Phase 7.0 (continuation scaffold, 2026-05-30)

**[Jarvis mode hybrid X→W path]**: 선택지 = X (tap-next via 재-⌥+Space) / Y (screen-change auto) / Z (in-bubble [다음] 버튼) / W (plan-first checklist). Workflow 8-agent design (research + 4 design + synthesis) 박음. **선택: Hybrid X v0.2 + W v0.3 + Y v0.4 보류**. 근거: X는 *affirmative user signal* 1:1 매핑으로 *user-in-the-loop 차별* maximally 유지 (Operator/Manus가 깨진 자리), 22-28h dev cost로 ship-mode 압축 timeline 안. Y는 senior 신뢰 *불가역* 손상 위험 (false-positive) + Electron AX 취약. W는 *correct asymptote*이나 38-52h → X의 SessionState actor 재사용으로 v0.3에 *추가*. *되돌리기 비용*: scaffold만 박은 7.0 단계 — additive 필드 (taskComplete/requiresConfirmation/stepActionSummary) + SessionState enum + IrreversibleActions keyword 뿐, *behavior change X*. 15분 안에 revert 가능. 5-stage evolution: v0.1 single-shot → v0.2 tap-next → v0.3 plan-first → v0.4 screen-change opt-in → v0.5 active monitoring (hybrid edge+cloud, ₩15-50k/월 viable).

**[Irreversible-action 2-layer gate]**: 송금/결제/삭제 같은 *되돌릴 수 없는 동작*에서 자동 advance 막아야. 옵션 = (a) LLM `requires_confirmation: true` schema만 / (b) backend hardcoded keyword post-filter만 / (c) **둘 다 OR로**. 선택 (c) — LLM이 한국어 변형 "이체하기"/"확정" 누락 가능 (synthesis risk #3), backend keyword가 강제 true. + v0.3에 app-exclusion list (1Password/카카오뱅크 bundleID) 3-layer gate. *되돌리기*: enum 1개 + Prompts 1 clause — 10분 revert.

**[Context bounded growth — text summary, not screenshot history]**: 옵션 = (a) Computer Use 식 full screenshot history (context window 폭주, token quadratic) / (b) stateless 매 call (v0.1) / (c) **rolling text summary** (≤30 words × 3 step = ~200 token). 선택 (c) — LLM이 본인 응답에 `step_action_summary` 박음, 다음 call의 `previousSteps`에 들어감. **bounded growth**. 4-step Slack task = 1 task당 input ~3000 token 안에. *되돌리기*: StepSummary struct 삭제 + AnalyzeRequest.previousSteps nil 강제 — 5분 revert.

## Phase 7.1 (continuation wire, 2026-05-30)

**[Same hotkey ⌥+Space — mode-aware 분기]**: 옵션 = (a) 새 hotkey (예 ⌥+.) 박음 / (b) 같은 ⌥+Space + state 분기. 선택 (b) — 사용자 학습 비용 0 (이미 익숙), state 분기는 `coordinator.snapshotState()` 1줄. 같은 keystroke이 *idle*에선 panel, *waitingForUserClick*에선 continueSession (panel skip, instruction 재사용). HUD 떠있고 그 외 state 시는 dismiss + cancelSession — *escape도 같은 키*. *되돌리기*: AppDelegate.handleHotkey 6줄 — 3분 revert.

**[Sentinel .cancelled → .idle 복귀]**: 옵션 = (a) `.cancelled` state 유지 / (b) cancelSession 끝에서 .idle 자동 sentinel. 선택 (b) — 다음 hotkey가 *자연스럽게 새 task path* (panel 띄움). `.cancelled` value는 log엔 박지만 state는 immediate idle. *되돌리기*: 1줄 — `sessionState = .idle` 제거. test도 같이.

**[Backend irreversible-action post-filter — run() 안에서 OR 강제]**: AnalyzeCoordinator.run 결과 처리 시 `IrreversibleActions.isIrreversible(...) || result.requiresConfirmation`로 safeResult 합성. LLM이 누락한 한국어 변형 (이체하기/확정/탈퇴) 잡힘. log `[safety] keyword post-filter`. 옵션 = (a) AppDelegate (UI layer) / (b) AnalyzeCoordinator (data layer). 선택 (b) — data invariant 한 곳에서 강제, AppDelegate는 *requires_confirmation 신뢰*. *되돌리기*: 12줄 — 5분 revert.

## Phase 7.2 (dispatcher fallback, 2026-05-31)

**[Gemini 429 → Claude 자동 fallback dispatcher]**: 사용자 Gemini 무료 *일당 20회* 도달 (Probe B 확정, CLAUDE.md 갱신). 옵션 = (a) 사용자가 수동 dispatcher swap (env 변경 + 재시작) / (b) 1 vendor 끝나면 사용자 에러 (현재) / (c) **wrapper dispatcher가 primary 429 시 자동 fallback**. 선택 (c) — 사용자 *zero-touch unblock*. `FallbackDispatcher`가 `LLMDispatcher` protocol 구현 → caller 무관. `shouldFallback(on:)` 결정 rule: `retriesExhausted(429)` / `httpStatus(429)` 만 swap, 다른 error는 throw (primary code bug 가능성). Claude `tool_use` forced JSON (`tool_choice: {type: "tool", name: "respond_with_analysis"}`) — Anthropic `responseSchema` 없는 대신 tool input schema 강제. AppDelegate가 env 키 조합으로 dispatcher 결정 (Gemini+Claude → Fallback / Gemini only / Claude only / 둘 다 없음). *되돌리기 비용*: FallbackDispatcher 삭제 + AppDelegate dispatcher 단일 복귀 — 15분 revert. 비용: Claude Sonnet ~$0.003/M input, Gemini의 30배지만 dogfooding ₩100-200/월 안 넘음. Gemini paid 활성화 후엔 Fallback 거의 안 trigger.

**[JSONValue + AnyEncodable for tool input_schema]**: Anthropic tool input_schema는 nested JSON object — Swift Codable struct 매핑 불편 (5+ depth, generic value types). 옵션 = (a) struct 5+ tier 박음 (boilerplate 60+ lines) / (b) `[String: Any]` (Sendable X) / (c) **`JSONValue` enum (`.string / .int / .bool / .array / .object`)** — recursive, Sendable, Encodable/Decodable 둘 다. 선택 (c) — Sendable 강제 (Swift 6 strict concurrency), input_schema dictionary 직접 표현, ClaudeResponseBlock.input도 같은 type. *되돌리기 비용*: ClaudeDispatcher 안 JSONValue 사용처 — 30분 revert.

## v0.3 (Notarized DMG path, 2026-06-02)

**[Mac App Store SKIP → Notarized DMG + Sparkle]**: Workflow w99oanivx 박은 진단. 옵션 = (a) Mac App Store 박음 (30% 수수료, 1-2주 review, sandbox 강제) / (b) **Notarized DMG + Sparkle 자동 update**. 선택 (b). 근거 4개: (1) **AXUIElement sandbox 충돌 fatal** — ScreenBridge가 *frontmost app의 element*를 읽으려면 Accessibility 권한 박는데 sandbox에선 *cross-process AX 호출 reject*. Rectangle / Hammerspoon / BetterTouchTool 동일 이유 App Store 안 박음. (2) ScreenCaptureKit sandbox 호환 단 *전체 화면 capture*는 entitlement 추가. (3) DMG = 30% 수수료 X + 무제한 update + Sparkle EdDSA 자유. (4) 한국 App Store 추가 요건 (KCC 위치 신고 / SiwA endpoint) ScreenBridge 해당 X. *추가 비용*: Apple Developer Program $99/년 (Notarization 필수) + GitHub Actions Sparkle pipeline (4h). *되돌리기 비용*: App Store target 박는 거 1-3개월 (entitlement / sandbox compat rewrite + 거절 round 3-5회). v0.5+에 *LLM-only mode SKU*로 App Store retry 검토 (AXUIElement 없는 형태).

**[SensitivityRouter — frontmost bundleID + fail-closed alert]**: v0.3 Layer 2 (5-layer 보안). 옵션 = (a) capture 후 image-level redact (image redact 복잡 + image-only ChatGPT vision call에 효과 X) / (b) **frontmost app bundle ID deny-list + fail-closed** / (c) 둘 다. 선택 (b) — *capture 전 차단* = cloud 호출 자체 X. 19개 deny-list (1Password 3개 + 한국 은행 7 + 한국 신용카드 4 + KeychainAccess + Mail + LastPass). hotkey 시점 NSWorkspace.frontmostApplication.bundleIdentifier 박음 (TriggerPanel canBecomeKey=false → trigger panel 떠도 frontmost 유지). `LLMRoutingDecision` enum 3 case (.cloud / .localOnly / .blockedLocalModelNotInstalled). v0.2 (Qwen 미박힘) = sensitive 시 .blockedLocalModelNotInstalled → cloud 차단 + Korean alert "🔒 이 앱은 보호 중이에요. 다음 업데이트(v0.3)에서 on-device 처리". v0.3 (Qwen 박힌 후) = .localOnly → Qwen dispatcher swap. *되돌리기 비용*: SensitivityRouter.swift 삭제 + AnalyzeCoordinator router 통과 7줄 revert + AnalyzeRequest.frontmostBundleID 4줄 — 10분.

**[한국 PII pattern 5개 추가 (SecretMasker v0.3)]**: 옵션 = (a) generic English-only pattern 유지 / (b) **한국 시장 fit으로 5 pattern 추가** (휴대폰 010-XXXX-XXXX, 은행 계좌, 사업자번호, 운전면허, 여권). 선택 (b) — target user (어머님 / 시니어 / 한국 기업) instruction에 한국 PII 박힐 가능성 ↑. 여권 (M/S prefix) + 사업자번호 (3-2-5) + 운전면허 (XX-XX-XXXXXX-XX) 형식. *false-positive risk*: 일반 전화번호 (02-XXX, 031-) 차단 위해 휴대폰만 (01[016789]) 매칭. 박는 거 6 → 11 pattern. *되돌리기 비용*: 5 pattern 삭제 — 1분.

**[Session Inspector — 별도 NSPanel + @MainActor ObservableObject]**: 사용자 quote (2026-06-02) "병렬로 뭔가 문맥 트래킹하는 기능을 따로 만들까 새로띄워서". 옵션 = (a) HUD에 박음 (HUD는 click-through라 사용자 *클릭 못 함*) / (b) menu-bar에만 짧은 진행률 / (c) **별도 floating NSPanel + SwiftUI** (사용자 클릭 가능, multi-monitor follow, ⌥⌘I toggle). 선택 (c) — 3 가치 (자녀가 어머님 옆 / 기업 audit / 본인 디버그) 모두 박힘. `InspectorState` @MainActor ObservableObject singleton — actor (AnalyzeCoordinator)에서 `Task { @MainActor in ... }`로 publish. 박힌 거: beginSession / markAnalyzing / appendStep / finishCompleted / finishCancelled / finishFailed. NSPanel styleMask `.utilityWindow + .nonactivatingPanel` + `level=.floating` + `collectionBehavior=[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` — *어머님 다른 앱 사용해도 follow*. menu-bar item "세션 진행 보기" + ⌥⌘I hotkey. *되돌리기 비용*: 3 file (InspectorState/View/Panel) + AnalyzeCoordinator 6 wire 호출 + AppDelegate 2 menu — 20분 revert.

**[ContentMasker Layer 2.5 — candidate filter vs image-level redact]**: Layer 1 (SecretMasker text) + Layer 2 (Router app)만으로는 *일반 앱 안에 박힌 카드/주민/계좌 row* (예: Cursor에서 .env 열려있고 sk- key 박힌 줄 표시 / Slack에서 친구가 카드번호 박은 메시지 / Notion 노트의 주민번호) 못 잡음. 옵션 = (a) image-level redact (OCR box 위 검은 사각형 그림 + LLM에 마스킹된 image 보냄) / (b) **candidate-level filter** (OCR/AX candidates 중 SecretMasker.detect 박힌 row 제외 — LLM이 그 row를 target_text로 못 잡음) / (c) 둘 다. 선택 (b) — image redact는 복잡 (Core Graphics + transparent box + 좌표 계산), Layer 4 (local Qwen) 박은 후 image 자체가 외부 안 감 → image-level redact 가치 작음. candidate filter는 *11 SecretMasker pattern 재사용* (sk-/AKIA/카드/주민/한국 PII 5개), 50 lines, 6 tests. LLM이 box 그릴 후보에서 *민감 row 빠짐* → "여기 [4111-XXXX-XXXX-XXXX] 누르세요" 안내 불가능. *되돌리기 비용*: ContentMasker.swift 삭제 + AnalyzeCoordinator 6줄 revert — 5분.

**[PrivacySettings — UserDefaults + 재시작 적용 vs runtime swap]**: 사용자 setting (Privacy mode toggle: auto/cloud/always-local) 박는 거 옵션 = (a) UserDefaults 박은 후 *재시작 후 적용* / (b) runtime swap (dispatcher chain 박은 후 *실행 중 바꿈*). 선택 (a) — runtime swap은 *FallbackDispatcher actor isolation* + *Qwen 첫 호출 2GB download* 동시 처리 복잡 (사용자가 cloud 모드 중인데 갑자기 local swap → 대기 시간 + UI 갱신). v0.3는 *재시작 알림* (SwiftUI alert), v0.4에 runtime swap 박음. `PrivacySettings.effectiveUseLocal()` static — env var (SCREENBRIDGE_USE_LOCAL) + setting 조합: auto → env 따라 / cloud → false / alwaysLocal → true. AppDelegate dispatcher 결정 시 호출. *되돌리기 비용*: 3 file (PrivacySettings + SettingsView + SettingsWindow) + AppDelegate 4줄 — 15분.

**[Region opt-out Layer 3 — CGContext fill vs CIImage filter vs SwiftUI overlay]**: 사용자가 박힌 *민감 영역* (예: 모니터 우상단 알림 영역 / 본인 얼굴 카메라 영역) 박는 옵션 = (a) **CGContext fill (검은 사각형 draw)** / (b) CIImage filter (gaussian blur) / (c) SwiftUI overlay (capture 박은 후 view 박음). 선택 (a) — image-level fill이 *외부 LLM 보낸 image 자체*에 박힘 → cloud LLM도 안 봄. blur (b)는 *읽기 가능* 가능성 (OCR 박음). overlay (c)는 *display에는 박힘* 단 *capture된 image*는 그대로 → cloud로 새음. fill은 *deterministic 검은 픽셀* → AI 절대 못 봄. PrivacySettings에 `sensitiveRegionsAll: [UInt32: [CGRect]]` display별 박음 (UserDefaults JSON persist). `nonisolated static sensitiveRegions(displayID:)`는 *MainActor isolation 우회* — ScreenCapture가 nonisolated context에서 호출 (UserDefaults thread-safe). `ScreenCapture.redactRegions(image:regions:screenFrame:sentSize:)` — screen-logical pt → sent-image pt scale + Y-flip (CGImage origin top-left vs AppKit bottom-left) + CGContext fill. UI (사용자가 *영역 그림*)는 v0.3.1 박음 — 현재 API만. *되돌리기 비용*: ScreenCapture 12줄 + PrivacySettings.sensitiveRegions* 30줄 — 10분.

**[ModelDownloadProgress — singleton ObservableObject + QwenLocalDispatcher publish]**: ~2GB Hugging Face download UX 옵션 = (a) silent log only (사용자 ⌥+Space 후 *기다림* X) / (b) URLSessionDownloadTask 직접 박음 + 자체 progress UI / (c) **mlx-swift-examples loadContainer progress callback + @MainActor ObservableObject singleton publish**. 선택 (c) — mlx 박은 download path 그대로 (자체 caching 박음 ~/Documents/huggingface) + progress callback에 Task { @MainActor in publish } 박음. SwiftUI ProgressView linear + ETA 계산 (elapsed / fraction → remaining) + 한국어 친화 ("약 X분 Y초 남음") + "이 화면 닫아도 다운로드 계속" 안심 메시지. SettingsView에 embed → 사용자 ⌘, 박은 후 *언제든 진행 상황 봄*. failed 시 reason + "다시 시도 또는 Cloud 모드로" 안내. *되돌리기 비용*: 2 file (Progress + View) + QwenLocalDispatcher 8줄 + SettingsView 5줄 — 10분.

---

**[Hotkey 200ms throttle — Probe C race guard]**: Workflow Probe C 발견 — ⌥+Space 빠르게 2번 → 두 Task spawn 동시 → 같은 state snapshot → 중복 dispatcher 호출 (RPM burst). 옵션 = (a) `isHandlingHotkey` boolean guard (in-flight check) / (b) **시간 기반 throttle (200ms)** / (c) 무시 (actor 직렬화로 OK). 선택 (b) — guard (a)는 long-running dispatcher (9s) 동안 사용자가 *완료 후 빠르게 다음* 막힘. 200ms는 사람 손가락 한계 (~100-150ms) 약간 위 — *의도적 반복*만 통과. throttle X (c)는 RPM burst 그대로 (Gemini quota 20/day 사용자 빨리 소진). *되돌리기 비용*: throttle 변수 삭제 + guard 삭제 — 2분 revert. 200 → 100ms or 500ms 조정 자유.

## Phase 7.3 (audit log + completion pill, 2026-05-31)

**[SessionAuditLog — per-session JSON file, not append-only log]**: 옵션 = (a) 단일 append-only log file (sessions.log) — 단순 / (b) **per-session JSON file** (`<uuid>.json`) — atomic write, parse 쉬움 / (c) SQLite — overkill. 선택 (b) — 매 step `atomic write` (session 진행 중도 디버그 가능), `~/Library/Application Support/com.screenbridge.app/sessions/`에 박힘, menu-bar "Open sessions folder" item이 *이미* 사용. `SessionAuditEntry.steps` 배열에 매 step append (instruction X reapply — `currentInstruction` 1회만 박힘). `Outcome` enum: inProgress / completed / cancelledByUser / cancelledByTimeout / error. 매 step + finalize 시 save. *screenshot 절대 X* — Phase 7.0 bounded growth 결정 일관 (text summary only). *되돌리기 비용*: file 삭제 + AnalyzeCoordinator의 auditEntry/save 호출 삭제 — 15분 revert. Phase 7.4 TODO: 7일 후 자동 삭제 (rotation).

**[Completion pill 초록 ✓ vs ErrorPill 재사용]**: 옵션 = (a) ErrorPill (빨강) 그대로 — 색만 message로 구분 / (b) **별도 CompletionPill (초록 + ✓)** — 명확. 선택 (b) — 사용자 *명확히 "성공적 완료"* 인식 (특히 시니어/non-tech). 초록 RGB(0.2, 0.65, 0.3) — accessible (WCAG AA contrast 흰 글씨). 2.5s auto-dismiss (Task.sleep 안에 `currentContent == .completion` check로 race 차단 — 새 task 떠있으면 dismiss X). *되돌리기 비용*: HUDContent.completion case + CompletionPill struct + HUDController.presentCompletion + auto-dismiss Task — 20줄 revert.

## v0.2 (보안 layer, 2026-05-31)

**[Secret regex mask at AnalyzeCoordinator.run boundary — instruction 박기 *전*]**: v0.2 보안 5-layer 첫 박음 (memory: product-vision-global-multi-platform). 옵션 = (a) ScreenCapture에 *image redact* — 화면 자체 secret 흐림 / (b) **AnalyzeCoordinator에 instruction + audit text mask** — LLM 외부 호출 전 + disk write 전 / (c) AppDelegate에 사용자 input 직후 mask. 선택 (b) — *data boundary* (외부 + 디스크) 정확히 1곳. (a) image redact는 v0.3+ (OCR 후 box-level redact 복잡). (c)는 *다른 path 또 박아야* (continuation의 history도 mask 필요 — 단 history는 LLM 자체 응답이라 secret 거의 X). SecretMasker 10 pattern (sk-/sk-ant-/sk-proj-/AIza/AKIA/github_pat_/ghp_/xox/PEM/주민번호/카드). *email은 mask X* — instruction "내 이메일 어디 입력?" 사용자 use case 보존. anti-false-positive: specific prefix 우선, broad pattern 피함 (예: 32-char hex 차단). *되돌리기 비용*: SecretMasker.swift 삭제 + AnalyzeCoordinator의 mask 호출 3곳 revert — 10분.

**[Email mask 보류 — instruction에 visible 유지]**: 옵션 = (a) email도 mask — 보수적 / (b) **email mask X — instruction에 visible 유지** / (c) audit log엔 mask, instruction엔 X. 선택 (b) — 사용자 "내 이메일 [user@x.com] 입력" 같은 instruction에서 email 유지 필요 (LLM이 *어디 입력*인지 인식). PII 보호는 *outgoing data*만 — instruction은 사용자 본인 의도, 사용자 본인 LLM API key에 가는 거. v0.3+ 사용자 *opt-in mask* 가능. *되돌리기*: email pattern 한 줄 추가 — 1분.

## v0.2 (local-first roadmap, 2026-05-31)

**[3-tier Hybrid: Cloud + Router + Local + Apple FM]**: 사용자 우려 정당 — 화면 전체 cloud → senior/기업 못 씀. Workflow `wiy4w4h3y` 5-agent survey 후 path 확정. 옵션 = (a) cloud only ship (Operator/Manus 자리, 차별 lose) / (b) 100% local ship (Apple FM vision 막힘 + Llama 4 Scout M1 8GB 불가 → 1-3개월 시간 lose) / (c) **3-tier hybrid (cloud default + SensitivityRouter deny-list fail-closed + Qwen2.5-VL-3B 민감 화면 → 추후 Apple FM swap)**. 선택 (c) — pragmatic-ship-mode 일치, LLMDispatcher protocol 박혀있어 swap 30분-2일, fail-closed 라우팅이 100% local보다 *감사 가능성* 측면 강력 (enterprise/B2G 통과 후보). v0.2 SensitivityRouter만 박혀도 senior + 기업 pilot 시작 가능. v0.3 Qwen local (1-3개월). v0.4 Apple FM (WWDC26 ~3주 후 발표 dependent — vision API 막힌 게 *blocker*, text-only confirmed). *되돌리기 비용*: SensitivityRouter 1 file + AnalyzeCoordinator 4줄 — 10분 revert. *Vendor roadmap에 의존 X*: Apple FM은 bonus 취급, v0.2/v0.3 일정 결정에 영향 X.

**[Qwen2.5-VL-3B 4-bit (mlx-swift-lm) over Llama 4 / Moondream / Gemma 3]**: Workflow 4-probe 비교. 옵션 = (a) Llama 4 Scout 17B (M1 32GB+ → 어머님 탈락 + EU license) / (b) Moondream 2 1.9B (Swift binding 없음 → Python subprocess → .app 단일 binary 깨짐) / (c) **Qwen2.5-VL-3B 4-bit via mlx-swift-lm** (Swift native, 1.9-2.2GB disk, 3-4GB RAM peak, M1 8GB 빠듯 가능, 정확도 ~80-85% vs Gemini) / (d) Gemma 3 4B swift-gemma-cli (단일 maintainer risk + responseSchema 부재) / (e) Apple FM (vision API 현재 막힘). 선택 (c) — 4 dim 모두 통과 (vision/Swift/M1 8GB/swift-native dep). 정확도 risk는 Probe D-prime (Week 1) 5장 fixture 빠른 sanity check로 GO/NO-GO 결정. <70%면 즉시 cloud-only ship으로 fallback. *되돌리기 비용*: QwenLocalDispatcher 삭제 + mlx-swift-lm dep 제거 — 30분.

## Phase 9.0 (Local-first 시작, 2026-05-31)

**[mlx-swift-examples (MLXVLM) over Python subprocess / Ollama HTTP]**: Local Qwen inference 옵션 = (a) Python subprocess (mlx-vlm) — .app 단일 binary 깨짐, ProcessIPC 추가 / (b) Ollama HTTP localhost — 사용자가 별도 daemon 설치 필요, ScreenBridge 단일 install 깨짐 / (c) **mlx-swift-examples MLXVLM Swift native dep** — Apple-official, M1 Metal GPU, single binary. 선택 (c) — pragmatic-ship-mode + .app 단일 install 일관. dep 추가 후 첫 resolve ~10s (mlx-swift 0.29.1 + 5 transitive: GzipSwift, swift-jinja, swift-collections, swift-numerics), 첫 build 63s (480 files, Metal kernel compile). 일반 build incremental ~3-5s. *되돌리기 비용*: Package.swift dep 1줄 제거 + QwenLocalDispatcher.swift 삭제 — 5분.

**[fixtures/sensitive_screens/ .gitignore *.png + README + instructions.json]**: 사용자 본인 dogfooding fixture (1Password / 카카오뱅크 / Mail / Slack / Notion 5장)는 *개인정보* — git commit 안 됨. 옵션 = (a) 모두 commit (synthetic fake 만들기) / (b) 모두 commit X (fixture 없음) / (c) **README + instructions.json만 commit, *.png는 .gitignore**. 선택 (c) — 사용자가 *실제 본인 화면*에서 박음 (Probe D-prime 진짜 정확도), instructions.json은 expected target + role + irreversible flag 박힘, README는 박는 방법 + GO/NO-GO criteria. *되돌리기 비용*: fixtures/sensitive_screens/ directory 삭제 — 1분.

**[QwenLocalDispatcher.analyze() mid-level path over ChatSession]**: MLXVLM 두 inference API = (a) ChatSession high-level (simpler, instructions: + respond(to:)) / (b) **mid-level container.perform + MLXLMCommon.generate(...)** (explicit GenerateParameters + .info event 직접 access). 선택 (b) — Phase 9 Probe D-prime GO/NO-GO에 *tokens/sec + token count 측정 필수* (ChatSession은 streamDetails(...) 안에 숨김), GenerateParameters를 *property assignment*로 정확 박음 (temperature 0.0, topP 0.001, maxTokens 512 — greedy-ish JSON). API drift 박은 거 4개 fix: (1) `images:` parameter 없음 → `Chat.Message.user(_:images:)` 안 박음 (2) `topK` 없음 → temperature 0 + topP 0.001로 effective greedy (3) `GenerateCompletionInfo.stopReason` 없음 → tokensPerSecond + tokens count만 log (4) `Memory.cacheLimit` 없음 → `MLX.GPU.set(cacheLimit:)` 사용. *되돌리기*: ChatSession path로 swap 30분.

**[Direct mlx-swift dep — transitive resolve X]**: mlx-swift-examples 박았는데 *MLX product re-export X* (transitive only). 옵션 = (a) `Memory.cacheLimit` (cache cap) 박지 X — OOM risk M1 8GB / (b) **mlx-swift 직접 dep 추가 + `.product(name: "MLX", package: "mlx-swift")`**. 선택 (b) — 5MB resolve 추가 비용, cache cap 박을 수 있음 (OOM 방지 critical). 또: MLX.GPU.set(cacheLimit:) API path 확인 후 wire. *되돌리기*: Package.swift 2줄 — 1분.

---

(다음 trade-off는 여기에 append. crate/모듈/패턴/dependency 선택은 5분짜리도 다 기록.)

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

(다음 trade-off는 여기에 append. crate/모듈/패턴/dependency 선택은 5분짜리도 다 기록.)

# CLAUDE.md

이 파일은 Claude Code가 매 세션 시작 시 자동으로 읽는다. **항상 가장 먼저 확인할 곳.**

## 프로젝트 정체
ScreenBridge — macOS 데스크톱 도구. AI가 시키는 추상적 지시를 사용자의 실제 화면에 맞는 구체적 지시로 실시간 번역한다.

## 매 세션 시작 시 무조건 실행할 순서

1. 이 CLAUDE.md 읽기 (지금 하고 있는 거)
2. `cat PRODUCT.md` — 무엇을, 왜 만드는지 방향 확인
3. `cat STATE.md` — 어디까지 했는지 확인
4. `cat SCRATCHPAD.md` — 미해결 질문 있는지 확인
5. `git log --oneline -20` — 최근 작업 흐름 확인
6. `git status` — uncommitted 있으면 위험. `git diff` 후 부분 작업이면 `git checkout -- .`
7. STATE.md의 "Next step"부터 작업 시작
8. `logs/build.log`에 "Session resumed at <ISO timestamp>, Phase X.Y" 한 줄 append

## 작업 진행 시 핵심 문서
- **PRODUCT.md** — 제품 비전과 방향. 거의 안 바뀜. 매 세션 첫 참조.
- **SPEC.md** — 구체 작업 스펙. Phase별로 따라가면 됨. (Tauri stack 기준 — Swift swap 후 SPEC update 필요.)
- **STATE.md** — 현재 상태. 매 commit과 함께 갱신.
- **SCRATCHPAD.md** — 막힌 곳, 사용자에게 물어볼 질문.
- **logs/build.log** — append-only 결정 로그. 절대 truncate 금지.
- **TROUBLESHOOTING.md** — 발견된 버그/이슈와 해결 과정. **모든 디버그 narrative가 가는 곳**. 학습 자산. stack swap 후에도 그대로 유지 — 함정은 stack 무관.
- **DECISIONS.md** — trade-off 있는 선택의 기록. 무엇을 골랐고 왜, 무엇을 안 골랐고 왜.
- **PROJECT_TIMELINE.md** — 전체 history (phase 전환, stack swap, 큰 결정 흐름). 사후 정리 금지, append-only.

## 회복력 규칙 핵심 (전체는 SPEC.md R1-R7 — 단 SPEC.md는 Tauri 기준 stale, STATE.md 우선)

- **R1**: 매 atomic 작업 후 즉시 commit.
- **R2**: STATE.md를 매 commit과 함께 갱신.
- **R3**: 새 세션 시작 시 위의 8단계 RESUME PROTOCOL. **단 step 2의 `cat PRODUCT.md` 다음 `cat STATE.md`가 가장 정확한 현재 상태 (SPEC.md stale).**
- **R4 (Swift)**: Commit 전 **`swift build` + `swift test`** 통과 필수. (과거 Tauri: `cargo check`, `tsc --noEmit`.)
- **R5**: 함수 body가 `todo!()`이거나 컴파일 안 되면 commit 금지. Blockers에만 기록.
- **R6**: 사용량 캡 가까울 때 새 큰 작업 시작 금지. atomic까지만 마무리, 아니면 stash.
- **R7**: Phase 완료 시 commit 메시지 = `Phase X.Y COMPLETE: <설명>`.
- **R8 (Troubleshoot-or-Forget)**: 디버그하는 동안 *어디서 막혔고 어떤 가설을 세웠고 무엇이 진짜 원인이었는지* 발견 즉시 `TROUBLESHOOTING.md`에 4-파트(증상/가설·시도/원인/해결+학습) 엔트리 추가. 미루지 말 것 — 다음 세션 자신에게 가장 값진 자산이다. 사후 정리 X, 디버그 끝나면 같은 commit에 포함.
- **R9 (Trade-off Trail)**: 두 개 이상의 합리적 선택지가 있고 그 사이에서 골랐다면 `DECISIONS.md`에 (선택지/Trade-off/선택/근거/되돌리기 비용) 5-파트 엔트리 추가. crate 선택, 모듈 위치, 디자인 패턴, 에러 처리 방식, 모델/dispatcher swap 등 전부. "그냥 더 깔끔해서"는 근거 X — 시간/돈/유지보수/학습 중 하나 이상의 축으로 justify할 것.

## 절대 규칙

1. **불확실하면 SCRATCHPAD.md에 질문 기록 후 다른 작업으로.** 추측 금지.
2. **fixtures/ 안의 데이터만 신뢰.** 외부 데이터 가정 금지.
3. **각 Phase verifier 통과해야 다음 Phase.** 3번 실패 시 SCRATCHPAD.md 기록 후 다음 Phase.
4. **새 디렉토리/패키지 임의 생성 금지.** SPEC.md의 구조 엄수.
5. **Swift macOS native app.** Tauri v0.1 attempt는 `tauri-archive` branch + `v0.1-tauri-attempt` tag로 보존. 새 작업은 Swift/SwiftUI/AppKit. SDK 표준 패턴 우선 — 추상화 우회 발견 시 SwiftUI 직접. (이전 룰 "Tauri 2.0만 사용"은 2026-05-27 `PROJECT_TIMELINE.md` 참조하여 swap.)
6. **Anthropic API 외 외부 LLM 라이브러리 v0.1에선 추가 금지.** (실측상 Gemini 무료 + sonnet 비교 필요 시 그것만 추가, 그 외 새 vendor 신중.)
7. **`logs/build.log`는 append-only.** 절대 truncate 금지.

## 사용자에게 멈춰서 물어볼 상황

다음일 때만 멈춤. 다른 모든 막힘은 SCRATCHPAD에 기록 후 다음 작업으로:
- API 키 401/403 (`.env` 문제)
- 동일 에러 3번 재시도해도 해결 안 됨
- macOS 권한 다이얼로그 요구되어 사용자 액션 필요
- fixtures/ 비어있음 또는 instructions.json 없음

SCRATCHPAD.md 형식:
```
## [TIMESTAMP] Phase X.Y — <간단 제목>
**시도한 것:** ...
**막힌 지점:** ...
**가능한 해결책:** ...
**사용자 답 필요:** ...
```

## 환경 (Swift swap 후, 2026-05-27)

- macOS 14+ (Sonoma) / 개발 환경은 macOS 26 (Tahoe)
- Swift 6.3 + Xcode 26 (`/Applications/Xcode.app`)
- SwiftPM (`swift build` / `swift run`). production `.app`은 swift-bundler 또는 Xcode (후속).
- `.env`에 `GEMINI_API_KEY` (채택 dispatcher) + `ANTHROPIC_API_KEY` (옵션). gitignore됨, 사용자 제공. 또는 셸 process env.
- **(과거) Rust+Cargo+Node+Tauri는 `tauri-archive` branch — main에 없음.**

## 모델 사용 (Swift 기준)

- **vision 호출 (채택): `gemini-2.5-flash`** (무료 **20 RPD** — 2026-05 기준, Google이 250 → 20 silent 변경. 8-15s). responseSchema로 JSON 강제 필수. *20 RPD 초과 시 일일 막힘* — 해결: GCP billing 활성화 또는 다른 project key 또는 Anthropic dispatcher swap.
- 대안: `claude-sonnet-4-6` (Anthropic API, 정확도 최고, 유료) / claude CLI subprocess (Pro 구독, 느림).
- Groq Llama 4 Scout 17B는 vision 76초 실측 → 폐기 (DECISIONS.md).
- 모델명 하드코딩하지 말고 `Sources/ScreenBridge/GeminiDispatcher.swift` 등에 const로.
- 좌표는 LLM 추정 X — Vision framework OCR + AXUIElement deterministic source (DECISIONS.md "99% 정확도 architecture").

## 한 줄 요약

PRODUCT.md = 왜. SPEC.md = 어떻게. STATE.md = 어디까지. SCRATCHPAD.md = 막힌 곳.
TROUBLESHOOTING.md = 무엇이 왜 깨졌고 어떻게 고쳤나. DECISIONS.md = 왜 이렇게 결정했나.

처음 네 개로 위치, 뒤 두 개로 학습. 매 세션 자체 보전.


## Project log (required, dual-write)

When you fix or decide something non-trivial in this repo, write BOTH of these in the same turn as the commit:

1. `docs/troubleshooting.md` — terse problem-indexed reference (Symptom / Cause / Fix / Commit / Pattern). Append a new entry below the `---` divider.
2. `content/logs/<project-slug>/<YYYY-MM-DD>-<short-slug>.mdx` — dated narrative with frontmatter:

```yaml
---
title: "Concrete one-line title"
date: "YYYY-MM-DD"
project: "jarvis-pc"
kind: "troubleshoot | tech-retro | ux-retro | business | monetization | update"
visibility: "public | unlisted | private"
language: "en"
summary: "One or two sentences."
tags: ["topic", "stack"]
---
```

### What counts as non-trivial

LOG IT: build/deploy errors, hidden coupling, dependency migrations, architecture or infra decisions, design/copy choices made on judgment, strategy or pricing memos.

DON'T LOG: routine renames, lint fixes, typo fixes, dependency bumps with no behavior change, formatting commits.

### Anti-hallucination rules (non-negotiable)

1. **Symptom is literal.** Paste the actual error/output in a fenced code block. No paraphrasing.
2. **Cause is verified.** Only state what you read in the actual code or ran in the actual command. If you guessed, write `Hypothesis: ...` and `Verified by: ...`. If unverifiable, omit Cause or mark `Suspected:` with an explicit caveat.
3. **Fix names actual files.** `git diff` is the source of truth. If `git diff` doesn't show the change, don't claim you made it.
4. **Commit hash AFTER committing.** Use `git rev-parse HEAD` after the commit lands. Never write a hash that doesn't exist yet.
5. **Date from git.** `git log -1 --format=%cI` for the commit time. For forward-looking entries (decisions being written in the moment), today's date from the session start. Never guess.
6. **Pattern is rare.** Only write a Pattern line if a recurring lesson is obvious from this one incident. Padding it with generic advice is worse than omitting.
7. **No fabricated metrics.** "Took about 60s" if you saw 60s. "Took 1m 23s exactly" only if you have the timestamp.

### Visibility defaults by kind

- `business`, `monetization` → `private` by default (strategy memos shouldn't ship accidentally)
- `knowledge`-style facts → `unlisted` if you have such a type
- Everything else → `public`

Override per entry in frontmatter.

### Skip rule for routine commits

The Stop hook blocks the turn until the most recent commit is either logged OR explicitly marked routine. To skip without writing an entry:

- Option A — put `[no-log]` (or `[skip-log]`) anywhere in the commit message. The hook auto-appends a `<!-- skipped: <hash> <subject> -->` line to `docs/troubleshooting.md` so it stops firing.
- Option B — append the same `<!-- skipped: <hash> <subject> -->` line yourself, then commit. Same effect.

Routine = typo fix, lint fix, formatting commit, dep bump without behavior change, file rename. Anything else: write the entry.
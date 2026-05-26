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
- **SPEC.md** — 구체 작업 스펙. Phase별로 따라가면 됨.
- **STATE.md** — 현재 상태. 매 commit과 함께 갱신.
- **SCRATCHPAD.md** — 막힌 곳, 사용자에게 물어볼 질문.
- **logs/build.log** — append-only 결정 로그. 절대 truncate 금지.

## 회복력 규칙 핵심 (전체는 SPEC.md R1-R7)

- **R1**: 매 atomic 작업 후 즉시 commit.
- **R2**: STATE.md를 매 commit과 함께 갱신.
- **R3**: 새 세션 시작 시 위의 8단계 RESUME PROTOCOL.
- **R4**: Commit 전 `cargo check`, `tsc --noEmit`, Phase verify 모두 통과 필수.
- **R5**: 함수 body가 `todo!()`이거나 컴파일 안 되면 commit 금지. Blockers에만 기록.
- **R6**: 사용량 캡 가까울 때 새 큰 작업 시작 금지. atomic까지만 마무리, 아니면 stash.
- **R7**: Phase 완료 시 commit 메시지 = `Phase X.Y COMPLETE: <설명>`.

## 절대 규칙

1. **불확실하면 SCRATCHPAD.md에 질문 기록 후 다른 작업으로.** 추측 금지.
2. **fixtures/ 안의 데이터만 신뢰.** 외부 데이터 가정 금지.
3. **각 Phase verifier 통과해야 다음 Phase.** 3번 실패 시 SCRATCHPAD.md 기록 후 다음 Phase.
4. **새 디렉토리/패키지 임의 생성 금지.** SPEC.md의 구조 엄수.
5. **Tauri 2.0만 사용.** Tauri v1 API 금지. Electron 절대 금지.
6. **Anthropic API 외 외부 LLM 라이브러리 v0.1에선 추가 금지.**
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

## 환경

- macOS 13+
- Rust + Cargo
- Node 20+ + npm
- Tauri 2.0
- `.env`에 ANTHROPIC_API_KEY (gitignore됨, 사용자가 제공)

## 모델 사용

- vision 호출: `claude-sonnet-4-6`
- 텍스트만 호출 시: `claude-haiku-4-5-20251001` (학습용 저렴)
- v0.1 코드에 모델명 하드코딩하지 말고 `src-tauri/src/dispatcher.rs`에 const로 둘 것

## 한 줄 요약

PRODUCT.md = 왜. SPEC.md = 어떻게. STATE.md = 어디까지. SCRATCHPAD.md = 막힌 곳.
이 네 개로 본인이 매 세션 자기 위치 파악.

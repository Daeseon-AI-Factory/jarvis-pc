# SCRATCHPAD — 미해결 질문 및 막힌 곳

미해결을 위쪽에. 해결되면 `## 해결됨` 섹션으로 이동하거나 제거.

---

## [2026-05-26] Phase 0.4 — Anthropic API 키 placeholder 상태
**시도한 것:** `.env` 읽음. 값: `ANTHROPIC_API_KEY=placeholder`.
**막힌 지점:** placeholder이므로 실제 API 호출 불가.
**가능한 해결책:**
- 사용자가 실제 키로 직접 `.env` 수정 (`ANTHROPIC_API_KEY=sk-ant-...`).
- 그때까지 모든 라이브 호출 의존 코드는 build/check 통과해야 하고, 테스트는 `#[ignore]` 또는 `is_api_key_available()` 가드.
**사용자 답 필요:** 사용자가 본인 페이스에 맞춰 키 추가. 빌드는 계속.

## [2026-05-26] Phase 1.2 / Phase 2.4 — fixture 이미지 부재
**시도한 것:** `fixtures/instructions.json`은 있음 (3개 항목: vercel_dashboard, aws_console, github_repo).
**막힌 지점:** 매칭되는 `.png` 파일 0개. dispatcher live 통합 테스트가 이미지 바이트 필요.
**가능한 해결책:**
- (a) 사용자가 본인 macOS 화면에서 캡처해 `fixtures/`에 둠 (실사용 환경 정확 반영).
- (b) Phase 1.2 `load_fixtures()`는 이미지 존재 여부 검증 분리 → 메타데이터만으로 통과.
- (c) Phase 2.4 테스트는 이미지 없으면 skip (이미 API 키 없으면 skip이므로 동일 가드).
**사용자 답 필요:** Phase 2.4 도달 시점에 사용자가 직접 캡처 제공 또는 placeholder 합성. 보류.

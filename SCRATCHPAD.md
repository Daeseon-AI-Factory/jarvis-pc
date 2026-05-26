# SCRATCHPAD — 미해결 질문 및 막힌 곳

미해결을 위쪽에. 해결되면 `## 해결됨` 섹션으로 이동하거나 제거.

---

## [2026-05-26] Phase 3.1 — Screen Recording 권한 다이얼로그 필요
**상태:** `capture_active_screen()` 구현 + `#[ignore]`-가드된 smoke test 추가. cargo check 통과.
**막힌 지점:** 실제 캡처 호출 시 macOS가 첫 회에 "Screen Recording 권한" 다이얼로그를 띄움. 자동 클릭 불가.
**가능한 해결책:**
- 사용자가 `cargo test --manifest-path src-tauri/Cargo.toml capture_active_screen_smoke -- --ignored --nocapture` 수동 실행 후 권한 승인.
- 또는 Phase 5 e2e 시점에 `npm run tauri dev`로 앱 띄우고 단축키 누르면 그때 다이얼로그 등장.
**사용자 답 필요:** 사용자가 Phase 3.1 verify를 manual 실행할 시점 선택. 빌드 차원에서는 cargo check + cargo build 성공으로 충분 (R5 R4 통과).

## [2026-05-26] Phase 1.2 / Phase 2.4 — fixture 이미지 부재
**시도한 것:** `fixtures/instructions.json`은 있음 (3개 항목: vercel_dashboard, aws_console, github_repo).
**막힌 지점:** 매칭되는 `.png` 파일 0개. dispatcher live 통합 테스트가 이미지 바이트 필요.
**가능한 해결책:**
- (a) 사용자가 본인 macOS 화면에서 캡처해 `fixtures/`에 둠 (실사용 환경 정확 반영).
- (b) Phase 1.2 `load_fixtures()`는 이미지 존재 여부 검증 분리 → 메타데이터만으로 통과 (이미 적용).
- (c) Phase 2.4 테스트는 이미지 없으면 skip (`is_api_key_available()` + image_path.exists() 가드).
**사용자 답 필요:** Phase 2.4 도달 시점에 사용자가 직접 캡처 제공 또는 placeholder 합성. 보류.

---

## 해결됨

### [2026-05-26] Phase 0.4 — Anthropic API 키 위치
**상태:** `.env`는 `ANTHROPIC_API_KEY=placeholder` 그대로지만 사용자의 셸 process env에 실제 키가 set됨 (length=108, 형식상 sk-ant-…). `anthropic_api_key()`가 process env를 우선 픽업하므로 `is_api_key_available()` returns true.
**라이브 호출:** 아직 안 했음 (`scripts/verify_key.sh` 실행 시 또는 Phase 2.4 dispatcher 통합 테스트에서 처음 호출 예정).
**관련 가드:** `placeholder_env_reports_unavailable` test가 process env 키 발견 시 즉시 skip.

### [2026-05-26] Phase 0.2 — tests/ 위치 SPEC와 다름
**SPEC.md 구조 트리:** `screenbridge/tests/dispatcher_tests.rs` (프로젝트 루트).
**실제 채택:** `src-tauri/tests/dispatcher_tests.rs`.
**이유:** Cargo integration tests는 crate 루트 (`src-tauri/Cargo.toml` 옆) 의 `tests/` 디렉토리에서 자동 발견. 루트에 두면 `cargo test --manifest-path src-tauri/Cargo.toml`이 못 찾는다. SPEC 위반 1건 — 작동 우선.

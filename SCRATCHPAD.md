# SCRATCHPAD — 미해결 질문 및 막힌 곳

미해결을 위쪽에. 해결되면 `## 해결됨`으로 이동하거나 제거.
**Stack은 Swift macOS native (2026-05-27 swap). Tauri 시절 항목은 아래 "해결됨/obsolete"로 이동.**

---

## ⚠️ [2026-05-28] SPEC.md가 Tauri 기준 stale — 새 세션 주의

**막힌 지점:** `SPEC.md`의 Phase 매트릭스 (0.1 tauri scaffold, R4 `cargo check`, 디렉토리 트리 `src-tauri/` 등)가 전부 Tauri 기준. Swift swap 후 stale. 새 세션이 SPEC.md 따라가면 Tauri 작업 시도 위험.
**처리:** **Swift 진행은 `STATE.md`의 "Next step" + Swift Phase 매트릭스 + `DECISIONS.md` 따름.** SPEC.md는 PRODUCT 본질 참조용으로만.
**해결책 후보:** SPEC.md를 Swift 기준 rewrite (task) 또는 SPEC_SWIFT.md 새로. 단일 사용자 dogfooding 단계라 우선순위 낮음 — STATE.md 매트릭스로 충분.

## [2026-05-28] disk 잔존 정리 — src-tauri/ 7.2GB + node_modules 84MB

**상태:** Tauri 코드는 git에서 삭제 (`32929bd`)됐지만 *working tree에 빌드 캐시 잔존*. gitignored이라 git status엔 `?? src-tauri/`만. source는 `tauri-archive` branch에 보존, `target/`은 재생성 가능한 빌드 결과물.
**해결책:** `rm -rf src-tauri node_modules` (안전 — source는 branch에, 빌드 캐시는 재생성). disk 7.3GB 확보.
**사용자 답 필요:** 정리해도 무방 (백업 tag/branch에 source 있음). 새 세션 또는 사용자가 실행.

## [2026-05-26] git pre-commit hook portable X

**상태:** `.git/hooks/pre-commit`이 R8/R9 + dual-write 강제 (코드 변경 staged인데 학습 자산 변경 없으면 차단). 정규식에 `.swift` + `docs/troubleshooting.md` + `content/logs/` 포함됨.
**막힌 지점:** `.git/`은 git tracking X. 다른 머신 clone 시 hook 사라짐.
**해결책:** `scripts/setup-hooks.sh`로 `git config core.hooksPath ./scripts/git-hooks` + scripts/git-hooks/ tracked. 또는 husky.
**사용자 답 필요:** 다른 환경 clone 시점에 결정.

## [2026-05-26] fixture 이미지 부재 (Swift도 동일)

**상태:** `fixtures/instructions.json` 3개 항목 (vercel/aws/github) 있지만 매칭 `.png` 0개.
**막힌 지점:** dispatcher live 통합 테스트가 이미지 바이트 필요.
**해결책:** 사용자가 본인 화면 캡처해 `fixtures/`에 두거나, Swift Phase 6 e2e 시점에 실제 캡처로 검증. metadata만으로 load 테스트는 통과 가능.
**사용자 답 필요:** Phase 6 도달 시점.

## [2026-05-26] Screen Recording 권한 (Swift Info.plist)

**상태:** Tauri는 Info.plist NSScreenCaptureUsageDescription 박았음. Swift는 SwiftPM이라 `.app` bundle 없으면 Info.plist 적용 어려움.
**해결책:** Phase 3.1 ScreenCaptureKit 도입 시 — dev `swift run`은 권한 첫 호출 시 다이얼로그. production `.app` bundle (swift-bundler 또는 Xcode) 시점에 Info.plist NSScreenCaptureUsageDescription 박음.
**사용자 답 필요:** Phase 3.1 + production 빌드 시점. dev 동안은 권한 다이얼로그 manual 승인.

---

## 해결됨 / obsolete (Tauri 시절)

### [obsolete] ocr.rs SPEC tree 위반 / macocr 설치
Tauri 시절 OCR architecture (macocr subprocess). Swift는 Vision framework `VNRecognizeTextRequest` 직접 — binary 설치 불필요. tauri-archive에 보존. Swift Phase 6.1에서 재구현 (find_box fuzzy matching 로직은 그대로 포팅).

### [obsolete] tests/ 위치 SPEC와 다름
Tauri Cargo integration test 위치 문제. Swift는 `Tests/ScreenBridgeTests/` (SwiftPM 표준). 무관.

### [해결됨, 유효] API 키 위치
`.env`는 `ANTHROPIC_API_KEY=placeholder`지만 사용자 셸 process env에 실제 키. 추가로 `GROQ_API_KEY` + `GEMINI_API_KEY`도 `.env`에 있음 (사용자가 추가). Swift는 `GEMINI_API_KEY` 사용 (Gemini Flash 채택). `.env` 또는 process env 둘 다 읽기.

### [obsolete] Phase 6.3 Settings minimal / Phase 3.1 cargo test 권한
Tauri 시절 항목. Swift Phase 매트릭스에서 재정의 (STATE.md).

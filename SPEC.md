# ScreenBridge v0.1 — Autonomous Build Spec (Tauri)

## 사명
여러 세션에 걸쳐 자율적으로 ScreenBridge v0.1 MVP를 완성한다. 사용량 한도로 세션이 예고 없이 잘릴 수 있다. 언제 잘려도 다음 세션이 정확히 이어갈 수 있게 작업한다.

## 제품 정의
PRODUCT.md 참조. 변경 금지.
요약: 글로벌 단축키 → 화면 캡처 + 사용자 입력 AI 지시 → Claude vision → 화면 위 반투명 오버레이로 가이드 표시. Mac 메뉴바 상주.

## 절대 규칙
1. 불확실하면 SCRATCHPAD.md에 질문 기록 후 다른 작업으로. 추측 금지.
2. fixtures/ 안에 있는 데이터만 신뢰. 외부 데이터 가정 금지.
3. 각 Phase verifier 통과해야 다음 Phase. 3번 실패 시 SCRATCHPAD.md 기록 후 다음 Phase.
4. 새 디렉토리/패키지 임의 생성 금지. 아래 구조 엄수.
5. Tauri 2.0 외 데스크톱 프레임워크 추가 금지. Tauri v1 API 사용 금지. Electron 절대 금지.
6. Anthropic API 외 외부 LLM 라이브러리 v0.1에선 추가 금지.

## 회복력 규칙 (R1-R7)

### R1: 매 atomic 작업 후 즉시 commit
atomic = 하나의 파일/기능이 consistent 상태가 되는 최소 단위.

### R2: STATE.md를 매 commit과 함께 갱신
형식:
```
# Current State

**Phase:** X.Y
**Last completed:** <한 줄 설명>
**Last commit:** <hash>
**Next step:** <다음 작업>
**Blockers:** <없음 또는 구체적>
**Last updated:** <ISO timestamp>

## Phase 완료 현황
- [x] / [ ] Phase 0.x
- [x] / [ ] Phase 1.x

## SCRATCHPAD 미해결: <숫자>
```

### R3: 새 세션 시작 시 RESUME PROTOCOL
1. `git log --oneline -20`
2. `cat STATE.md`
3. `cat SCRATCHPAD.md` — 미해결 영역 작업 금지
4. `git status` — uncommitted 있으면 `git diff` 후 부분 작업이면 `git checkout -- .`
5. STATE.md의 "Next step"부터
6. logs/build.log에 "Session resumed at <timestamp>, Phase X.Y" append

### R4: Commit 전 자가 검증 필수
- 변경된 모든 Rust 파일 `cargo check` 통과
- 변경된 모든 TS 파일 `tsc --noEmit` 통과
- 해당 Phase verify 명령 통과
- 통과 안 되면 commit 금지

### R5: Commit 금지 상태
- 함수 body가 `todo!()` 또는 placeholder
- Rust/TS 컴파일 안 됨
- import한 crate 설치 안 됨
→ STATE.md Blockers에 기록만

### R6: 사용량 캡 가까울 때
응답 느려짐 신호:
1. 진행 중 atomic까지 마무리 → commit
2. 아니면 `git stash` (메시지 명확히)
3. STATE.md Blockers에 stash 정보 + commit

### R7: Phase 경계 commit
완료 시 메시지: `Phase X.Y COMPLETE: <설명>`

### 로그 규칙
`logs/build.log` append-only. 절대 truncate 금지.
형식: `<ISO timestamp> | <Phase> | <action> | <result>`

---

## 프로젝트 구조 엄수
```
screenbridge/
├── PRODUCT.md
├── SPEC.md
├── README.md (Phase 6에서 생성)
├── SCRATCHPAD.md
├── STATE.md
├── BUILD_REPORT.md (전체 완료/시간 종료 시)
├── .env (사용자가 만듦)
├── .gitignore
├── fixtures/
│   ├── *.png
│   └── instructions.json
├── logs/
│   └── build.log
├── src/ (React + TS 프론트엔드)
│   ├── App.tsx
│   ├── components/
│   │   ├── TriggerPanel.tsx
│   │   └── Overlay.tsx
│   ├── lib/
│   │   └── ipc.ts
│   └── main.tsx
├── src-tauri/ (Rust 백엔드)
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   └── src/
│       ├── main.rs
│       ├── lib.rs
│       ├── capture.rs
│       ├── dispatcher.rs
│       ├── prompts.rs
│       ├── hotkey.rs
│       ├── tray.rs
│       ├── overlay.rs
│       ├── sessions.rs
│       └── fixtures.rs
├── tests/
│   └── dispatcher_tests.rs
└── package.json
```

---

## Phase 0: Bootstrap

### 0.1 Tauri 프로젝트 스캐폴드
`npm create tauri-app@latest` 사용. 옵션: 프로젝트 이름 screenbridge, 프론트엔드 React + TypeScript, package manager npm.
**Verify:** `npm install && cargo check --manifest-path=src-tauri/Cargo.toml` 둘 다 통과
**Commit:** `Phase 0.1: tauri scaffold`

### 0.2 추가 구조
위 디렉토리 트리의 빈 stub 파일들 생성. SCRATCHPAD.md, STATE.md 초기화. logs/build.log 헤더 한 줄.
**Commit:** `Phase 0.2: structure`

### 0.3 .gitignore
```
.env
node_modules/
target/
dist/
.DS_Store
*.log
!logs/build.log
```
fixtures/*.png는 트래킹 (!fixtures/*.png)
**Commit:** `Phase 0.3: gitignore`

### 0.4 API 키 검증 (선택적)
`scripts/verify_key.sh`: Anthropic API 한 번 호출.
- `.env`에 ANTHROPIC_API_KEY 존재하고 valid면 검증 통과
- `.env`에 키 없거나 placeholder("여기에_본인_API_키" 등)면 **SCRATCHPAD.md에 "API 키 설정 필요 - 사용자가 빌드 후 추가 예정" 기록하고 Phase 0.5로 진행**
- 401/403 에러면 SCRATCHPAD에 기록 후 Phase 0.5로 진행
- 빌드 멈추지 말 것
**Commit:** `Phase 0.4: API key check (deferred OK)`

### 0.5 macOS 권한 설정
`src-tauri/tauri.conf.json` 및 Info.plist에 필요 권한 명시:
- Screen Recording (NSScreenCaptureUsageDescription)
- Accessibility (필요 시)
- Input Monitoring (클립보드용, v0.2에서)
**Commit:** `Phase 0 COMPLETE: bootstrap`

---

## Phase 1: Foundation

### 1.1 로깅
- Rust: `tracing` crate, `logs/build.log`에 append
- TS: 간단 logger, Tauri IPC로 Rust 측 전달
**Verify:** 양쪽에서 로깅 → 파일에 두 줄
**Commit:** `Phase 1.1: logging`

### 1.2 Fixture loader
`src-tauri/src/fixtures.rs`:
```rust
pub struct Fixture {
    pub image_path: PathBuf,
    pub ai_instruction: String,
    pub expected_keywords: Vec<String>,
}
pub fn load_fixtures() -> Result<Vec<Fixture>, FixtureError>;
```
fixtures/instructions.json 파싱 (serde).
**Verify:** `tests/dispatcher_tests.rs`에서 load_fixtures() → 길이 >= 1
**Commit:** `Phase 1.2: fixture loader`

### 1.3 Config 관리
.env 로딩, API 키 추출.
- 키 없거나 placeholder면 dispatcher 인스턴스화 시점에만 에러 (모듈 로드 시점엔 에러 X)
- `is_api_key_available() -> bool` 헬퍼 함수 제공
**Commit:** `Phase 1.3: config`

---

## Phase 2: Core Pipeline (LLM Dispatcher)

### 2.1 Prompts
`src-tauri/src/prompts.rs`:

SYSTEM_PROMPT:
```
당신은 사용자의 화면을 보고, 사용자가 받은 AI 지시를 사용자의 실제 화면 상황에 맞게 번역하는 도우미다.

원칙:
1. 화면에 실제로 보이는 요소만 참조.
2. 추상 지시 금지. 구체 지시만 ("지금 화면의 왼쪽 사이드바 상단 'X' 클릭").
3. 화면이 AI 지시의 어느 단계인지 먼저 판단. 안 맞으면 명시.
4. 대상 UI 요소의 대략적 좌표 (x, y, width, height) 제공.
5. JSON 외 텍스트 금지:
{
  "screen_state": "...",
  "next_action": "...",
  "coordinates": [x, y, w, h] 또는 null,
  "reasoning": "..."
}
```

### 2.2 LLMDispatcher trait
`src-tauri/src/dispatcher.rs`:
```rust
#[async_trait]
pub trait LLMDispatcher: Send + Sync {
    async fn analyze(&self, image_bytes: Vec<u8>, instruction: String) 
        -> Result<AnalysisResult, DispatchError>;
}

pub struct AnalysisResult {
    pub screen_state: Option<String>,
    pub next_action: Option<String>,
    pub coordinates: Option<[i32; 4]>,
    pub reasoning: Option<String>,
    pub raw: String,
}
```

### 2.3 AnthropicDispatcher
- 모델: claude-sonnet-4-6
- HTTP via reqwest
- 이미지 base64 인코딩
- JSON 파싱, 실패 시 raw만
- 모든 호출 로그 기록

### 2.4 Fixture 기반 테스트
`tests/dispatcher_tests.rs`: 모든 fixture → analyze() → expected_keywords가 next_action에 포함되는지.

**API 키 처리:**
- `is_api_key_available()` 체크
- 키 없으면 테스트 함수에 `#[ignore]` 또는 early return + 로그 출력 ("Skipped: no API key, run after key setup")
- 키 있으면 정상 실행

**Verify:** 
- 키 있을 때: `cargo test` 통과
- 키 없을 때: `cargo test` 통과하되 "ignored" 또는 "skipped" 메시지 보임
- 어느 쪽이든 Phase 3 진입 가능
**Commit:** `Phase 2 COMPLETE: dispatcher (tests deferred if no key)`

---

## Phase 3: Screen Capture + System Integration

### 3.1 Screen capture
적절한 Rust crate 조사 후 선택. 후보: screencapturekit-rs, xcap, scap. 선택 기준: macOS 13+ 지원, 활성 윈도우만 캡처 가능, PNG 출력.
함수: `capture_active_screen() -> Result<Vec<u8>, CaptureError>`.
첫 호출 시 macOS 권한 다이얼로그 처리.
**Verify:** 명령 호출 → tmp 파일 저장 → 크기 > 1KB
**Commit:** `Phase 3.1: capture`

### 3.2 Global hotkey
Tauri globalShortcut 플러그인. 기본 ⌥+Space. 트리거 시 이벤트 발행.
**Verify:** 단축키 누르면 로그에 한 줄
**Commit:** `Phase 3.2: hotkey`

### 3.3 메뉴바 트레이
`src-tauri/src/tray.rs`. 메뉴: "Trigger now", "Settings", "Quit".
**Verify:** 실행 시 아이콘 표시, 메뉴 동작
**Commit:** `Phase 3 COMPLETE: system integration`

---

## Phase 4: UI - Trigger Panel

### 4.1 Trigger Panel 윈도우
글로벌 단축키 또는 트레이 "Trigger now" → 작은 윈도우:
- 텍스트 입력 박스 (멀티라인): "AI가 뭐라 했나?"
- [Analyze] 버튼
- [Cancel] 버튼

### 4.2 IPC 흐름
프론트 [Analyze] → 백엔드 analyze IPC → 화면 캡처 + dispatcher 호출 → 결과 프론트.
분석 중 로딩 상태 표시.
**Verify:** 수동 테스트 (단축키 → 입력 → Analyze → 결과)
**Commit:** `Phase 4 COMPLETE: trigger panel`

---

## Phase 5: UI - Overlay Window

### 5.1 오버레이 윈도우
Tauri 별도 윈도우:
- transparent: true
- decorations: false
- alwaysOnTop: true
- skipTaskbar: true
- 전체 화면
- mouseEvents 무시 (클릭 통과)

### 5.2 오버레이 컨텐츠
- coordinates 있으면 → 그 위치 반투명 빨간 박스
- 텍스트 풍선: next_action + reasoning
- 클릭 또는 ESC → 닫힘
- CSS fade-in, 박스 pulse

### 5.3 전체 흐름
Trigger Panel [Analyze] → 백엔드 → 결과 → Trigger 닫힘 → Overlay 등장.
**Verify:** 단축키 → 텍스트 → Analyze → 오버레이 표시 → ESC로 닫힘
**Commit:** `Phase 5 COMPLETE: overlay`

---

## Phase 6: Data Collection + Polish

### 6.1 세션 저장
`src-tauri/src/sessions.rs`:
저장 위치: `~/Library/Application Support/ScreenBridge/sessions/<YYYY-MM-DD>/<uuid>/`
- screen.png
- instruction.txt
- response.json
- meta.json (timestamp, active_app, feedback=null)

### 6.2 피드백
오버레이에 1-탭 ⬆⬇. 누르면 meta.json feedback 갱신.

### 6.3 Settings UI
단축키 변경, 세션 폴더 열기, 세션 wipe.

### 6.4 README.md
- 한 줄 설명
- 셋업 (.env, Xcode CLI tools, 권한)
- 실행 (`npm run tauri dev`)
- 알려진 한계 (단일 Space, macOS 13+)
**Commit:** `Phase 6 COMPLETE: ready for daily use`

---

## 최종: BUILD_REPORT.md
- 완료 Phase 목록 (timestamp)
- 미완료/스킵 + 이유
- SCRATCHPAD 미해결 요약
- 사용자 최초 확인 명령
- v0.2 후보
# ScreenBridge

AI가 시키는 추상적 지시를 사용자의 실제 화면에 맞는 구체적 지시로 실시간 번역하는 macOS 데스크톱 도구.

자세한 제품 정의는 [`PRODUCT.md`](PRODUCT.md), 빌드 spec은 [`SPEC.md`](SPEC.md), 현재 진행 상태는 [`STATE.md`](STATE.md).

## 셋업 (one-time)

1. **macOS 13 이상**, Apple Silicon 또는 Intel.
2. **Xcode Command Line Tools** — `xcode-select --install` (이미 있으면 skip).
3. **Rust toolchain** — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`.
4. **Node 20+** — `nvm install 20` 또는 [nodejs.org](https://nodejs.org) installer.
5. **Anthropic API 키** — `.env` 생성 후 `ANTHROPIC_API_KEY=sk-ant-...` 한 줄. 또는 셸 환경변수로 export — 둘 다 인식된다.
6. **권한 (첫 실행 시 다이얼로그)**
   - Screen Recording — `System Settings → Privacy & Security → Screen Recording`에서 ScreenBridge 허용. 미허용이면 화면 캡처 단계에서 에러로 끝남.

## 실행

```bash
npm install
npm run tauri dev
```

처음 컴파일은 Rust 의존성 빌드로 ~3분. 두 번째부터는 캐시되어 ~10초.

빌드가 끝나면 메뉴바에 트레이 아이콘이 떠 있다.

### 흐름

1. **트리거** — 기본 단축키 `⌥ Space` 또는 트레이 메뉴의 *Trigger now*.
2. **입력** — Trigger Panel이 화면 중앙에 뜨면 textarea에 AI가 준 지시를 붙여넣고 **Analyze**.
3. **결과** — Trigger Panel이 닫히고 화면 전체에 transparent overlay가 깔린다. 좌표가 나오면 그 자리에 빨간 박스가, 우하단에 다음 행동 + 이유 bubble이 뜬다.
4. **피드백** — bubble의 ⬆/⬇ 으로 좋고나쁨 1탭 기록. `~/Library/Application Support/com.screenbridge.app/sessions/<date>/<uuid>/meta.json`에 저장.
5. **닫기** — overlay 빈 공간 클릭 또는 `ESC`.

### 세션 데이터

각 `Analyze` 1회당 다음 파일을 같은 디렉토리에 남긴다:

- `screen.png` — 캡처된 화면
- `instruction.txt` — 입력 텍스트
- `response.json` — 구조화된 분석 결과
- `meta.json` — `{ timestamp_unix, timestamp_iso, feedback }`

트레이 메뉴 *Open sessions folder* 로 Finder에서 바로 열림.

## 알려진 한계 (v0.1)

- macOS 단일 Space만. 다중 Space는 v0.5 진입 조건.
- 화면 캡처는 primary monitor 한 장만. 멀티 모니터는 후속 Phase.
- Settings UI는 트레이 항목 하나 (Open sessions folder). 단축키 재바인딩, 세션 wipe, 자동 시작은 v0.2.
- 자동 클립보드 모니터링, 활성 앱 인식 — v0.2.
- 브라우저 확장 (ChatGPT / Claude.ai / Gemini DOM에서 자동 추출) — v0.3.
- 모델은 `claude-sonnet-4-6` (vision)로 하드 픽스. 모델 스왑은 `src-tauri/src/dispatcher.rs`의 `VISION_MODEL` 상수 한 줄.

## 개발

| 명령 | 효과 |
| ---- | ---- |
| `npm run tauri dev` | dev 모드로 앱 띄움 (HMR + Rust 컴파일) |
| `cargo check --manifest-path src-tauri/Cargo.toml` | Rust 빠른 타입체크 |
| `npx tsc --noEmit` | TypeScript 타입체크 |
| `cargo test --manifest-path src-tauri/Cargo.toml` | 모든 unit + integration 테스트 |
| `cargo test ... capture_active_screen_smoke -- --ignored` | 실제 화면 캡처 smoke (Screen Recording 권한 필요) |
| `./scripts/verify_key.sh` | Anthropic 키 1회 유효성 확인 |

## 라이선스 / 사용자

본인용 (dogfooding). 일주일 자발적 사용 ≥ 5회가 v0.2 진입 조건. 그 전엔 다른 사용자 고려 안 함.

# ScreenBridge

AI가 시키는 추상적 지시를 사용자의 실제 화면에 맞는 구체적 지시로 실시간 번역하는 macOS 데스크톱 도구.

상세: [PRODUCT.md](PRODUCT.md) (왜) / [SPEC.md](SPEC.md) (어떻게) / [STATE.md](STATE.md) (어디까지) / [PROJECT_TIMELINE.md](PROJECT_TIMELINE.md) (history) / [DECISIONS.md](DECISIONS.md) (왜 그렇게 결정) / [TROUBLESHOOTING.md](TROUBLESHOOTING.md) (디버그 학습 자산).

## 현재 stack: Swift macOS native

```
앱 셸      Swift 6.3 + SwiftUI + AppKit
플랫폼      macOS 14 (Sonoma) 이상
캡처        ScreenCaptureKit
좌표        AXUIElement (Accessibility) 또는 Vision framework OCR
LLM         Anthropic API (claude-sonnet-4-6 vision) / Gemini 2.5 Flash
빌드        SwiftPM (cargo-style) + swift run으로 dev
```

이전 **Tauri v0.1 attempt**는 [tauri-archive branch](https://github.com/Daeseon-AI-Factory/jarvis-pc/tree/tauri-archive) + `v0.1-tauri-attempt` tag 영구 보존. swap 근거는 [DECISIONS.md](DECISIONS.md) "STACK SWAP" entry + [PROJECT_TIMELINE.md](PROJECT_TIMELINE.md).

## 셋업 (one-time)

1. **macOS 14 (Sonoma) 이상** + Apple Silicon 권장.
2. **Xcode 26 이상** (App Store에서 설치, Swift 6.3 포함).
3. **Anthropic 또는 Gemini API 키** — `.env` 또는 셸 export.
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   # 또는 무료 옵션
   GEMINI_API_KEY=AIza...
   ```
4. **권한** (앱 첫 실행 시 다이얼로그):
   - Screen Recording — ScreenCaptureKit
   - Accessibility — AXUIElement (좌표 정확도)

## 실행 (dev)

```bash
git clone https://github.com/Daeseon-AI-Factory/jarvis-pc.git
cd jarvis-pc
swift build
swift run
```

또는 Xcode로 열기:
```bash
xed .
```

`swift run`은 dev 사이클 (cargo-style). production .app bundle은 후속 `swift-bundler` 또는 Xcode build로.

## 흐름 (Phase 4-5 완성 후 예상)

1. 트리거 — 기본 단축키 `⌥ Space` 또는 NSStatusItem 메뉴 *Trigger now*.
2. 입력 — Trigger Panel이 cursor 있는 monitor에 등장. textarea에 AI 지시 붙여넣고 *Analyze*.
3. 결과 — Panel 닫히고 *그 monitor에* transparent HUD overlay. AXUIElement로 정확한 좌표에 빨간 박스 + bubble (다음 행동 + 이유). 마우스는 desktop으로 통과.
4. 피드백 — bubble 클릭 또는 별도 단축키 (NSWindow accept mouse만 부분 영역).
5. 닫기 — `⌥ Space` 다시 또는 ESC.

각 회차 데이터는 `~/Library/Application Support/com.screenbridge.app/sessions/<date>/<uuid>/`.

## 알려진 한계 (v0.1)

- macOS 단일 Space 가정 (Tauri attempt에서 multi-monitor 깸 → Swift도 cursor monitor만).
- icon-only 버튼 (text 없음) 좌표 인식 약함 → AXUIElement로 v0.2 개선.
- production .app bundle은 후속 단계 (현재 `swift run`만).

## v0.1 Tauri attempt 결과

`BUILD_REPORT.md` + `PROJECT_TIMELINE.md` 참조. 30+ commits, 16개 layer 발견 후 Swift swap 결정. 학습 자산 (`TROUBLESHOOTING.md` + `DECISIONS.md`) 보존.

## 라이선스 / 사용자

본인용 (dogfooding). 일주일 자발적 사용 5회 ≥ 시 v0.2 진입.

# Sensitive Screens — Probe D-prime fixtures (Phase 9.0 Week 1)

Qwen2.5-VL-3B 4-bit local 정확도 *first sanity check*. 사용자가 *어머님 use case*를 시뮬레이션해서 5장 screenshot 박음.

## 사용자가 박을 5 screenshot

각 screenshot은 *실제 민감 화면* — 단 dogfooding 후 *git commit X* (개인정보).
fixtures/sensitive_screens/.gitignore에 `*.png` 박혀있어 commit 안 됨.
README + instructions.json만 commit.

### 1. `1-1password-vault.png`
- 1Password 또는 Bitwarden vault 화면
- 비밀번호 entries list visible
- 1개 entry 선택해서 *복사 button* 보임
- instruction: "비밀번호 복사 어떻게?"
- expected target: "복사" 또는 "Copy" button

### 2. `2-kakaobank-transfer.png`
- 카카오뱅크 (또는 Toss / 다른 은행) app 화면
- "이체" 또는 "송금" page
- 받는 사람 + 금액 입력 필드 보임
- instruction: "송금 어떻게?"
- expected target: "다음" 또는 "이체하기" button
- ⚠️ requires_confirmation=true 박혀야

### 3. `3-mail-compose.png`
- Mail.app (또는 Outlook / Gmail) compose window
- "To:" 필드 + "Subject:" + body
- "Send" button 보임
- instruction: "이메일 보내기 어떻게?"
- expected target: "보내기" 또는 "Send"

### 4. `4-slack-dm.png`
- Slack DM 화면 (친구와 채팅)
- private 메시지 visible
- "Send" button + 메시지 입력창
- instruction: "메시지 보내기 어떻게?"

### 5. `5-notion-page.png`
- Notion page (또는 비슷한 노트 앱)
- 본문에 *secret-like* 텍스트 박음 (가짜):
  - "API key: sk-FAKE_TEST..." (split, 진짜 X)
  - "주민번호: 901101-1234567" (가짜)
- instruction: "이 노트에 새 줄 추가 어떻게?"
- expected: SecretMasker가 *image 자체*에서 못 함 — Layer 4 local만 안전

## 박는 방법

```
1. 사용자가 본인 Mac에서 진짜 민감 화면 *그대로* 열어둠
2. macOS Screenshot tool (⌘+Shift+5) → "Capture Selected Window"
3. 저장: ~/Documents/screenbridge-fixtures/<N>-<name>.png
4. 이 path 박음 (gitignore — git 안 박힘)
```

## Probe D-prime 실행 (Week 1)

```swift
// 의사 코드 — Week 2-3에 실제 박음
for fixture in fixtures {
    let geminiResult = try await GeminiDispatcher().analyze(
        imageData: pngData,
        imageSize: size,
        instruction: fixture.instruction
    )
    let qwenResult = try await QwenLocalDispatcher().analyze(
        imageData: pngData,
        imageSize: size,
        instruction: fixture.instruction
    )
    
    compare(
        geminiTarget: geminiResult.targetText,
        qwenTarget: qwenResult.targetText,
        expected: fixture.expectedTarget
    )
}
```

## GO/NO-GO decision (Week 1 끝)

```
정확도 ≥ 80%: 진행 (Phase 9.0 Week 2-3 wire)
정확도 70-80%: 조심, 다른 model 평가 (Gemma 3 / InternVL)
정확도 < 70%: fallback (cloud Gemini + SensitivityRouter v0.2 ship)
```

## Anti-leak 정책

- screenshot은 *.gitignore* 안 박힘
- README + instructions.json 만 commit
- 사용자 본인 dogfooding 환경에서만 박음
- 다른 사람 정보 박지 X (자기 본인 vault / 자기 은행만)

# ScreenBridge Landing Page

Single-page static HTML. 외부 dep 0 (Pretendard font CDN만). 사용자 본인 박은 product identity + 5-layer 보안 + Apple 모델 lens 반영.

## 박힌 거

- `index.html` — single page, inline CSS, no JS framework
- 외부 dep: Pretendard font (Google Fonts CDN) — 한국어 fit
- ~600 lines, ~25KB

## Sections

1. **Hero** — "AI가 시키는 거, 화면에 박아드려요" + Mail.app mockup (박스 + bubble)
2. **Problem** — 사용자 quote "어르신들도 가이드 필요하잖아" + 시장 진단
3. **Differentiator (3-card)** — 안내만 / 100% on-device / 어머님 fit
4. **Compare** — Claude CU / Operator / Manus / Recall / Apple Intelligence vs ScreenBridge
5. **5-Layer Security** — 박힘/박는 중 명시 (Layer 1+5 done / 2/3/4 진행 중)
6. **Roadmap** — v0.1 ~ v0.5 (현재 v0.3 박는 중 표시)
7. **Waitlist** — email signup (현재 stub, 박을 거 TBD)
8. **Footer** — GitHub + 보안 playbook + deep dive link

## 미박힌 거 / 다음

- **Waitlist backend** — 현재 alert만. 박을 거 옵션:
  - Formspree 무료 tier
  - Mailchimp / ConvertKit
  - GitHub Discussions / Issues subscribe
  - 자체 backend (overkill v0.3)
- **분석** — Plausible 또는 Umami (privacy-friendly)
- **Demo video** — v0.3 출시 후 실 화면 녹화
- **다국어** — 영어 버전 (글로벌 시장 박는 시점)
- **OG image** — Twitter / 카톡 share 시 미리보기
- **Favicon** — 안경 SF Symbol 디자인 옮김

## 박는 방법

```
# 로컬 확인:
open /Users/daeseonyoo/Documents/GitHub/ai-product/jarvis-pc/landing/index.html

# 또는 dev server (Python):
cd landing && python3 -m http.server 8080
→ http://localhost:8080
```

## 배포 옵션

- **GitHub Pages** — `landing/` directory를 main branch에서 또는 별도 branch
- **Vercel / Netlify** — directory `landing/`, build command 없음 (static)
- **자체 도메인** — `screenbridge.app` (현재 없음, 박을 거)

## Style 컨셉

- **Apple-style minimal** — system font + 큰 typography + 넓은 spacing
- **Pretendard** — 한국어 fit, 깨끗
- **Red dot** — ScreenBridge brand (박스 빨강 + 사용자 본인 결정 lens)
- **Hover transitions** — 부드러운 0.15s
- **Mobile responsive** — 760px breakpoint
- **No tracking** — Google Analytics / Facebook Pixel 박지 X

## 박은 메시지 핵심

- "AI 시대지만 어머님은 어디 누르나요?" — target user pain
- "빅테크 안 잡는 자리" — Operator/Manus/CU 깨진 자리 위치 명시
- "100% on-device" — Layer 4 진짜 답 표시
- "안내만, 자동 X" — user-in-the-loop 영원 차별
- "5-layer 보안" — Apple 신뢰 모델 visual

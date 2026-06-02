#!/bin/bash
#
# ScreenBridge DMG 박는 script — Beta 배포용.
# build-app.sh 박은 후 호출.
#
# 사용:
#   ./scripts/build-dmg.sh
#   → ./dist/ScreenBridge-0.3.0-Beta.dmg
#

set -euo pipefail

cd "$(dirname "$0")/.."
DIST="$PWD/dist"
APP="$DIST/ScreenBridge.app"

VERSION="${DMG_VERSION:-0.3.0-Beta}"
DMG="$DIST/ScreenBridge-$VERSION.dmg"
STAGING="$DIST/dmg-staging"

if [[ ! -d "$APP" ]]; then
    echo "[build-dmg] $APP 박지 X — ./scripts/build-app.sh 먼저 박음" >&2
    exit 1
fi

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"

cp -R "$APP" "$STAGING/ScreenBridge.app"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/README.txt" <<'EOF'
ScreenBridge — AI 추상 지시를 화면에 박는 번역기

설치:
  1. ScreenBridge.app을 Applications 폴더로 드래그
  2. Applications에서 더블클릭
  3. 첫 실행 시 macOS "확인되지 않은 개발자" 경고:
     → Applications의 ScreenBridge.app 우클릭 → "열기"
     → 다음 dialog에서 "열기"
  4. Screen Recording / Accessibility 권한 dialog 박힘 - 둘 다 허용

사용:
  Alt+Space  AI 지시 입력 -> 화면에 박스 + 한국어 안내
  Cmd+,      환경설정 (Privacy mode + Local Model + 민감 영역)
  Alt+Cmd+I  Session Inspector (별도 panel)
  Alt+Cmd+R  민감 영역 편집 (드래그로 박음)

보안 모드 (100% Mac 안에서만):
  Cmd+, -> Privacy mode -> "Local only (안전)" -> 재시작
  첫 Alt+Space -> ~2GB Qwen2.5-VL-3B HF download (5-10분, 한 번만)
  다운 후 100% on-device

GitHub: https://github.com/Daeseon-AI-Factory/jarvis-pc
EOF

hdiutil create \
    -volname "ScreenBridge $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$STAGING"

echo "[build-dmg] ok - $DMG"
ls -lh "$DMG"

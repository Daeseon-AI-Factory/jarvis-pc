#!/usr/bin/env bash
# ScreenBridge dev — build + run + log 한 명령.
#
# 사용:
#   ./dev.sh           build + launch. ⌥+Space로 trigger panel. 종료는 Ctrl+C.
#
# 매번 'cd ~/Documents/GitHub/ai-product/jarvis-pc' 외우기 귀찮으면 alias (한 번만):
#   echo "alias sb='cd $(pwd) && ./dev.sh'" >> ~/.zshrc
#   source ~/.zshrc
# 그 다음 어디서든 'sb' 한 글자.

set -e
cd "$(dirname "$0")"

echo "→ swift build"
swift build

# ad-hoc codesign + --identifier 명시 — TCC가 cdhash + identifier로 정체성 기억.
# --identifier 없으면 매 build cdhash 변경 → TCC 권한 재요청 loop (verify workflow HIGH finding).
# 처음 실행 시 macOS Settings > Privacy > Screen Recording에 'ScreenBridge' 추가 + 토글 ON.
BIN_PATH="$(swift build --show-bin-path)/ScreenBridge"
if [ -f "$BIN_PATH" ]; then
  codesign --force --sign - --identifier com.screenbridge.dev "$BIN_PATH" 2>/dev/null || true
fi

echo ""
echo "→ swift run  (⌥+Space → trigger panel. 로그가 줄줄 보임. 종료는 Ctrl+C.)"
echo "──────────────────────────────────────────────────────────────────────"
exec swift run ScreenBridge

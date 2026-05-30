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

# ad-hoc codesign — TCC가 path 대신 binary identity 기억해 권한 매 빌드 재요청 안 함.
# 처음 실행 시 macOS Settings > Privacy > Screen Recording에 'ScreenBridge' 항목 추가 + 토글 ON.
BIN_PATH="$(swift build --show-bin-path)/ScreenBridge"
if [ -f "$BIN_PATH" ]; then
  codesign --force -s - "$BIN_PATH" 2>/dev/null || true
fi

echo ""
echo "→ swift run  (⌥+Space → trigger panel. 로그가 줄줄 보임. 종료는 Ctrl+C.)"
echo "──────────────────────────────────────────────────────────────────────"
exec swift run ScreenBridge

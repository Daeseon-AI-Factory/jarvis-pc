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

echo ""
echo "→ swift run  (⌥+Space → trigger panel. 로그가 줄줄 보임. 종료는 Ctrl+C.)"
echo "──────────────────────────────────────────────────────────────────────"
exec swift run ScreenBridge

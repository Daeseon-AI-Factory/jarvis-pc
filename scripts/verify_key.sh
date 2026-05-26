#!/usr/bin/env bash
# verify_key.sh — ANTHROPIC_API_KEY가 유효한지 한 번만 확인.
# SPEC Phase 0.4: 키 없거나 placeholder거나 401/403이어도 빌드를 멈추지 않는다 (exit 0).
# 그 경우 호출자(빌더)는 SCRATCHPAD.md에 기록 후 다음 Phase로 진행한다.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "[verify_key] .env 없음. SKIP." >&2
  exit 0
fi

# .env 로딩 (공백 / 따옴표 안전)
set -a
# shellcheck disable=SC1091
source .env
set +a

KEY="${ANTHROPIC_API_KEY:-}"

case "$KEY" in
  ""|"placeholder"|*"여기"*|*"YOUR"*|*"your-api-key"*)
    echo "[verify_key] ANTHROPIC_API_KEY가 placeholder/빈 값. SKIP (정상, 사용자 추가 대기)." >&2
    exit 0
    ;;
esac

echo "[verify_key] 키 발견, Anthropic messages endpoint 1회 호출…" >&2
RESP=$(mktemp)
STATUS=$(curl -sS -o "$RESP" -w '%{http_code}' \
  https://api.anthropic.com/v1/messages \
  -H "x-api-key: $KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}') || STATUS="curl-error"

case "$STATUS" in
  200)
    echo "[verify_key] OK (HTTP 200)" >&2
    rm -f "$RESP"
    exit 0
    ;;
  401|403)
    echo "[verify_key] 인증 실패 (HTTP $STATUS). SCRATCHPAD에 기록 후 진행." >&2
    cat "$RESP" >&2 || true
    rm -f "$RESP"
    exit 0
    ;;
  *)
    echo "[verify_key] 예상치 못한 응답 (HTTP $STATUS):" >&2
    cat "$RESP" >&2 || true
    rm -f "$RESP"
    exit 0
    ;;
esac

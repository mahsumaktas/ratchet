#!/usr/bin/env bash
# ar-stop-summary.sh — Stop hook: emits autoresearch progress summary

AR_ACTIVE_FLAG="/tmp/ar-active-${PPID}.txt"
AR_ROOT_CACHE="/tmp/ar-root-${PPID}.txt"

[ -f "$AR_ACTIVE_FLAG" ] || exit 0

ROOT=$(cat "$AR_ROOT_CACHE" 2>/dev/null || exit 0)
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

# Find scripts directory
SCRIPTS_DIR="${HOME}/.claude/skills/autoresearch/scripts"
[ -d "$SCRIPTS_DIR" ] || SCRIPTS_DIR="$(dirname "$0")/../scripts"

PROGRESS=$("$SCRIPTS_DIR/ar-report.sh" progress 2>/dev/null || echo "?")

python3 -c "
import json
msg = '[RATCHET PROGRESS] $PROGRESS'
print(json.dumps({'systemMessage': msg}))
" 2>/dev/null

exit 0

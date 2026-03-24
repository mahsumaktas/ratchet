#!/usr/bin/env bash
# ar-stop-summary.sh — Stop hook: emits autoresearch progress summary
set -euo pipefail

[ -f "/tmp/ar-active-${PPID}.txt" ] || exit 0

ROOT=$(cat "/tmp/ar-root-${PPID}.txt" 2>/dev/null) || exit 0
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

SCRIPTS_DIR="${HOME}/.claude/skills/autoresearch/scripts"
[ -d "$SCRIPTS_DIR" ] || SCRIPTS_DIR="$(dirname "$0")/../scripts"

PROGRESS=$("$SCRIPTS_DIR/ar-report.sh" progress 2>/dev/null || echo "?")

# Cost report
COST=$("$SCRIPTS_DIR/ar-cost.sh" total 2>/dev/null || echo "N/A")

AR_PROGRESS="$PROGRESS" AR_COST="$COST" python3 -c "
import json, os
print(json.dumps({'systemMessage': '[RATCHET PROGRESS] ' + os.environ['AR_PROGRESS'] + ' | Cost: ' + os.environ.get('AR_COST', 'N/A')}))
" 2>/dev/null

exit 0

#!/usr/bin/env bash
# ar-compact-inject.sh — PostCompact hook: injects autoresearch state after context compaction
set -euo pipefail

[ -f "/tmp/ar-active-${PPID}.txt" ] || exit 0

ROOT=$(cat "/tmp/ar-root-${PPID}.txt" 2>/dev/null) || exit 0
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

AR_STATE_FILE="$STATE_FILE" AR_ROOT="$ROOT" python3 -c "
import json, os

with open(os.environ['AR_STATE_FILE']) as f:
    s = json.load(f)

mode = s.get('mode', '?')
exp = s.get('experiment', 0)
state = s.get('state', '?')
kept = s.get('kept', 0)
disc = s.get('discarded', 0)
strategy = s.get('strategy', 'default')

# Read checkpoint preview
cp_path = os.path.join(os.environ['AR_ROOT'], '.autoresearch', 'CHECKPOINT.md')
cp = ''
if os.path.exists(cp_path):
    with open(cp_path) as f:
        cp = f.read()[:1000]

msg = (f'[RATCHET CONTEXT RESTORED] Active session detected after compaction.\n'
       f'Mode: {mode} | Exp: {exp} | State: {state} | K:{kept} D:{disc} | Strategy: {strategy}\n\n'
       f'CHECKPOINT preview:\n{cp}\n\n'
       f'CRITICAL: Read .autoresearch/CHECKPOINT.md immediately. Continue from state {state}. DO NOT restart bootstrap.')

print(json.dumps({'systemMessage': msg}))
" 2>/dev/null

# Log compact injection
SCRIPT_DIR="${HOME}/.claude/skills/autoresearch/scripts"
if [ -f "$SCRIPT_DIR/_lib.sh" ]; then
  # shellcheck source=scripts/_lib.sh
  source "$SCRIPT_DIR/_lib.sh"
  ar_log "info" "compact-inject" "injected"
fi

exit 0

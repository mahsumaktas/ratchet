#!/usr/bin/env bash
# ar-compact-inject.sh — PostCompact hook: injects autoresearch state after context compaction

AR_ACTIVE_FLAG="/tmp/ar-active-${PPID}.txt"
AR_ROOT_CACHE="/tmp/ar-root-${PPID}.txt"

[ -f "$AR_ACTIVE_FLAG" ] || exit 0

ROOT=$(cat "$AR_ROOT_CACHE" 2>/dev/null || exit 0)
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

python3 -c "
import json, os

with open('$STATE_FILE') as f:
    s = json.load(f)

mode = s.get('mode', '?')
exp = s.get('experiment', 0)
state = s.get('state', '?')
kept = s.get('kept', 0)
disc = s.get('discarded', 0)
strategy = s.get('strategy', 'default')

# Read checkpoint preview
cp_path = os.path.join('$ROOT', '.autoresearch', 'CHECKPOINT.md')
cp = ''
if os.path.exists(cp_path):
    with open(cp_path) as f:
        cp = f.read()[:1000]

msg = f'''[RATCHET CONTEXT RESTORED] Active session detected after compaction.
Mode: {mode} | Exp: {exp} | State: {state} | K:{kept} D:{disc} | Strategy: {strategy}

CHECKPOINT preview:
{cp}

CRITICAL: Read .autoresearch/CHECKPOINT.md immediately. Continue from state {state}. DO NOT restart bootstrap.'''

print(json.dumps({'systemMessage': msg}))
" 2>/dev/null

exit 0

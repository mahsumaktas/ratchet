#!/usr/bin/env bash
# ar-session-restore.sh — SessionStart hook: restores autoresearch state
# Matcher: startup|resume

STATE_FILE="$PWD/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

# Read state safely
STATE=$(AR_PATH="$STATE_FILE" python3 -c "
import json, os
with open(os.environ['AR_PATH']) as f:
    print(json.load(f).get('state',''))
" 2>/dev/null)
[ -n "$STATE" ] || exit 0
[ "$STATE" = "STOP" ] && exit 0

# Set active flags
echo "$PWD" > "/tmp/ar-active-${PPID}.txt"
echo "$PWD" > "/tmp/ar-root-${PPID}.txt"

# Build context summary safely via env var
AR_STATE_FILE="$STATE_FILE" AR_PWD="$PWD" python3 -c "
import json, os

with open(os.environ['AR_STATE_FILE']) as f:
    s = json.load(f)

mode = s.get('mode', '?')
exp = s.get('experiment', 0)
state = s.get('state', '?')
kept = s.get('kept', 0)
disc = s.get('discarded', 0)
strategy = s.get('strategy', 'default')
branch = s.get('branch', '?')

# Last 3 experiments
tsv_path = os.path.join(os.environ['AR_PWD'], '.autoresearch', 'results.tsv')
last_exps = ''
if os.path.exists(tsv_path):
    with open(tsv_path) as f:
        lines = f.readlines()[-3:]
        last_exps = ' | '.join([l.strip()[:80] for l in lines])

msg = (f'[RATCHET SESSION RESTORED] Mode: {mode} | Experiment: {exp} | State: {state} '
       f'| Kept: {kept} | Discarded: {disc} | Strategy: {strategy} | Branch: {branch}\n'
       f'Last experiments: {last_exps}\n'
       f'Read .autoresearch/CHECKPOINT.md and SKILL.md, then continue from state {state}. DO NOT restart bootstrap.')

print(json.dumps({'systemMessage': msg}))
" 2>/dev/null

# Log restore event
SCRIPT_DIR="${HOME}/.claude/skills/autoresearch/scripts"
if [ -f "$SCRIPT_DIR/_lib.sh" ]; then
  source "$SCRIPT_DIR/_lib.sh"
  CURRENT_STATE=$(AR_PATH="$STATE_FILE" python3 -c "
import json, os
with open(os.environ['AR_PATH']) as f:
    print(json.load(f).get('state',''))
" 2>/dev/null)
  ar_log "info" "session-restore" "restored" "state=$CURRENT_STATE"
fi

exit 0

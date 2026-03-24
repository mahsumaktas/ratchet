#!/usr/bin/env bash
# ar-session-restore.sh — SessionStart hook: restores autoresearch state
# Matcher: startup|resume

STATE_FILE="$PWD/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

STATE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('state',''))" 2>/dev/null)
[ -n "$STATE" ] || exit 0
[ "$STATE" = "STOP" ] && exit 0

# Set active flags
echo "$PWD" > "/tmp/ar-active-${PPID}.txt"
echo "$PWD" > "/tmp/ar-root-${PPID}.txt"

# Build context summary
SUMMARY=$(python3 -c "
import json
with open('$STATE_FILE') as f:
    s = json.load(f)

mode = s.get('mode', '?')
exp = s.get('experiment', 0)
state = s.get('state', '?')
kept = s.get('kept', 0)
disc = s.get('discarded', 0)
strategy = s.get('strategy', 'default')
branch = s.get('branch', '?')

# Last 3 experiments from results.tsv
import os
tsv_path = os.path.join('$PWD', '.autoresearch', 'results.tsv')
last_exps = ''
if os.path.exists(tsv_path):
    with open(tsv_path) as f:
        lines = f.readlines()[-3:]
        last_exps = ' | '.join([l.strip()[:80] for l in lines])

checkpoint_preview = ''
cp_path = os.path.join('$PWD', '.autoresearch', 'CHECKPOINT.md')
if os.path.exists(cp_path):
    with open(cp_path) as f:
        checkpoint_preview = f.read()[:500]

msg = f'''[RATCHET SESSION RESTORED] Mode: {mode} | Experiment: {exp} | State: {state} | Kept: {kept} | Discarded: {disc} | Strategy: {strategy} | Branch: {branch}
Last experiments: {last_exps}
Read .autoresearch/CHECKPOINT.md and SKILL.md, then continue from state {state}. DO NOT restart bootstrap.'''

print(json.dumps({'systemMessage': msg}))
" 2>/dev/null)

echo "$SUMMARY"
exit 0

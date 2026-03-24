#!/usr/bin/env bash
# ar-metrics-collector.sh — PostToolUse hook: auto-runs metrics after edit
# Matcher: Write|Edit|MultiEdit
# Automatically runs frozen metrics, guard, and decision engine after code edits.

AR_ACTIVE_FLAG="/tmp/ar-active-${PPID}.txt"
AR_ROOT_CACHE="/tmp/ar-root-${PPID}.txt"

# Fast exit if autoresearch not active
[ -f "$AR_ACTIVE_FLAG" ] || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Skip .autoresearch/ file edits
[[ "$FILE_PATH" == *".autoresearch/"* ]] && exit 0

ROOT=$(cat "$AR_ROOT_CACHE" 2>/dev/null || exit 0)
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

CURRENT_STATE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('state',''))" 2>/dev/null)

# Only run metrics when in MAKE_CHANGE state
[ "$CURRENT_STATE" = "MAKE_CHANGE" ] || exit 0

# Find scripts directory
SCRIPTS_DIR="${HOME}/.claude/skills/autoresearch/scripts"
[ -d "$SCRIPTS_DIR" ] || SCRIPTS_DIR="$(dirname "$0")/../scripts"
[ -d "$SCRIPTS_DIR" ] || exit 0

# Transition to VALIDATE
"$SCRIPTS_DIR/ar-state.sh" transition VALIDATE >/dev/null 2>&1 || exit 0

# Run metrics
metrics=$("$SCRIPTS_DIR/ar-metrics.sh" run 2>/dev/null) || metrics="{}"

# Run guard
guard_result=$("$SCRIPTS_DIR/ar-guard.sh" run 2>/dev/null) || guard_result='{"passed":true}'
guard_passed=$(echo "$guard_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('passed', True))" 2>/dev/null)

# Run decision engine
decision=$("$SCRIPTS_DIR/ar-decide.sh" "$guard_passed" 2>/dev/null) || decision='{"decision":"KEEP","reason":"metrics unavailable"}'

# Transition to DECIDE
"$SCRIPTS_DIR/ar-state.sh" transition DECIDE >/dev/null 2>&1 || true

# Compare with best for delta string
state_json=$(cat "$STATE_FILE")
delta_str=$(python3 -c "
import json
state = json.loads('''$state_json''')
best = state.get('best', {})
latest = json.loads('''$metrics''')
dec = json.loads('''$decision''')

parts = []
for key in ['test', 'lint', 'type', 'build']:
    b = best.get(key, '')
    l = latest.get(key, '')
    if b and l and str(b) != str(l):
        parts.append(f'{key}: {b}->{l}')
    elif b and l:
        parts.append(f'{key}: {l} (=)')

guard_str = 'PASS' if dec.get('guard_passed', True) else 'FAIL'
verdict = dec.get('decision', '?')
reason = dec.get('reason', '?')

msg = f'[RATCHET METRICS] {\" | \".join(parts) if parts else \"no change\"} | guard: {guard_str} | DECISION: {verdict} ({reason})'
print(json.dumps({'systemMessage': msg}))
" 2>/dev/null)

echo "$delta_str"
exit 0

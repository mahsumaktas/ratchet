#!/usr/bin/env bash
# ar-metrics-collector.sh — PostToolUse hook: auto-runs metrics after edit
# Matcher: Write|Edit|MultiEdit

# Fast exit if autoresearch not active
[ -f "/tmp/ar-active-${PPID}.txt" ] || exit 0

SCRIPT_DIR="${HOME}/.claude/skills/autoresearch/scripts"
[ -f "$SCRIPT_DIR/_lib.sh" ] || exit 0
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

INPUT=$(cat)
ar_parse_hook_input "$INPUT"

# Skip .autoresearch/ file edits
[[ "$FILE_PATH" == *".autoresearch/"* ]] && exit 0

ROOT=$(cat "$AR_ROOT_CACHE" 2>/dev/null) || exit 0
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

CURRENT_STATE=$(ar_state_get "state")

# Only run metrics when in MAKE_CHANGE state
[ "$CURRENT_STATE" = "MAKE_CHANGE" ] || exit 0

# Transition to VALIDATE
"$SCRIPT_DIR/ar-state.sh" transition VALIDATE >/dev/null 2>&1 || exit 0

# Run metrics
metrics=$("$SCRIPT_DIR/ar-metrics.sh" run 2>/dev/null) || metrics="{}"

# Run guard
guard_result=$("$SCRIPT_DIR/ar-guard.sh" run 2>/dev/null) || guard_result='{"passed":true}'
guard_passed=$(AR_GUARD_JSON="$guard_result" python3 -c "
import json, os
d = json.loads(os.environ.get('AR_GUARD_JSON', '{}'))
print('true' if d.get('passed', True) else 'false')
" 2>/dev/null) || guard_passed="true"

# Run decision engine
decision=$("$SCRIPT_DIR/ar-decide.sh" "$guard_passed" 2>/dev/null) || decision='{"decision":"KEEP","reason":"metrics unavailable"}'

# Transition to DECIDE
"$SCRIPT_DIR/ar-state.sh" transition DECIDE >/dev/null 2>&1 || true

# Log experiment
AR_EXP_ID=$(ar_state_get "experiment") \
AR_STRATEGY=$(ar_state_get "strategy") \
AR_TARGET_FILE=$(ar_state_get "current_target" 2>/dev/null) \
AR_METRICS_BEFORE=$(cat "$ROOT/.autoresearch/metrics/best.json" 2>/dev/null) \
AR_METRICS_AFTER="$metrics" \
AR_GUARD_PASSED="$guard_passed" \
AR_DECISION=$(echo "$decision" | python3 -c "import json,sys; print(json.load(sys.stdin).get('decision',''))" 2>/dev/null) \
AR_REASON=$(echo "$decision" | python3 -c "import json,sys; print(json.load(sys.stdin).get('reason',''))" 2>/dev/null) \
  ar_log_experiment

# Build summary message safely using env vars
AR_STATE_FILE="$STATE_FILE" AR_METRICS="$metrics" AR_DECISION="$decision" python3 -c "
import json, os

with open(os.environ['AR_STATE_FILE']) as f:
    state = json.load(f)
best = state.get('best', {})
latest = json.loads(os.environ['AR_METRICS'])
dec = json.loads(os.environ['AR_DECISION'])

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
" 2>/dev/null

exit 0

#!/usr/bin/env bash
# ar-decide.sh — Mechanical decision engine for Ratchet
# This is NOT an LLM judgment — it's a deterministic script.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

root=$(ar_project_root)
state_path=$(ar_state_path)
latest_path="$root/.autoresearch/metrics/latest.json"
guard_passed="${1:-true}"

decision_output=$(AR_STATE="$state_path" AR_LATEST="$latest_path" AR_GUARD="$guard_passed" python3 -c "
import json, os

with open(os.environ['AR_STATE']) as f:
    state = json.load(f)
best = state.get('best', {})

with open(os.environ['AR_LATEST']) as f:
    latest = json.load(f)

guard_ok = os.environ['AR_GUARD'].lower() == 'true'
improved = False
worsened = False

for key in ['test', 'lint', 'type', 'build']:
    b = best.get(key, '')
    l = latest.get(key, '')
    if not b or not l:
        continue
    if key == 'build':
        if str(l).strip() == '0' and str(b).strip() != '0':
            improved = True
        elif str(l).strip() != '0' and str(b).strip() == '0':
            worsened = True
        continue
    try:
        bi, li = int(b), int(l)
        if key == 'test':
            if li > bi: improved = True
            elif li < bi: worsened = True
        else:
            if li < bi: improved = True
            elif li > bi: worsened = True
    except (ValueError, TypeError):
        pass

# Check if all metrics errored
error_count = sum(1 for k in ['test','lint','type','build'] if latest.get(k,'') == 'error')
total_count = sum(1 for k in ['test','lint','type','build'] if latest.get(k,''))

if not guard_ok:
    decision, reason = 'DISCARD', 'guard command failed'
elif total_count > 0 and error_count == total_count:
    decision, reason = 'DISCARD', 'all metrics errored'
elif worsened:
    decision, reason = 'DISCARD', 'metrics worsened'
elif improved:
    decision, reason = 'KEEP', 'metrics improved'
else:
    # Metrics same — check code size
    import subprocess, re
    root = os.path.dirname(os.path.dirname(os.environ['AR_STATE']))
    stat = subprocess.run(['git', 'diff', '--stat'], capture_output=True, text=True, cwd=root).stdout
    m_ins = re.search(r'(\d+) insertion', stat)
    m_del = re.search(r'(\d+) deletion', stat)
    ins = int(m_ins.group(1)) if m_ins else 0
    dels = int(m_del.group(1)) if m_del else 0
    net = ins - dels
    if net > 0:
        decision, reason = 'DISCARD', f'metrics same but code grew (+{net} lines)'
    else:
        decision, reason = 'KEEP', f'metrics same, code reduced ({net} lines)' if net < 0 else 'metrics same, no size change'

deltas = []
for key in ['test', 'lint', 'type', 'build']:
    b, l = best.get(key, ''), latest.get(key, '')
    if b and l and str(b) != str(l):
        deltas.append(f'{key}: {b}->{l}')

print(json.dumps({
    'decision': decision,
    'reason': reason,
    'guard_passed': guard_ok,
    'deltas': deltas,
    'improved': improved,
    'worsened': worsened
}, indent=2))
" 2>/dev/null)

echo "$decision_output"

# Threshold-based self-review trigger
eval "$(ar_state_get_multi consecutive_discards experiment 2>/dev/null)" || true
consec="${consecutive_discards:-0}"
total="${experiment:-0}"
if [ "${consec:-0}" -ge 5 ] || { [ "${total:-0}" -gt 0 ] && [ $((total % 20)) -eq 0 ]; }; then
  "$SCRIPT_DIR/ar-self-review.sh" threshold 2>/dev/null || true
fi

# Record lesson from decision (single python3 + single state read)
eval "$(echo "$decision_output" 2>/dev/null | python3 -c "
import json, sys, shlex
d = json.load(sys.stdin)
print(f'dec_value={shlex.quote(d.get(\"decision\",\"\"))}')
print(f'dec_reason={shlex.quote(d.get(\"reason\",\"\"))}')
" 2>/dev/null)" || { dec_value=""; dec_reason=""; }

eval "$(ar_state_get_multi strategy current_target 2>/dev/null)" || true
strategy="${strategy:-default}"
target="${current_target:-unknown}"

if [ "$dec_value" = "KEEP" ]; then
  "$SCRIPT_DIR/ar-lessons.sh" add "KEEP: strategy=$strategy file=$target reason=$dec_reason" 2>/dev/null || true
fi

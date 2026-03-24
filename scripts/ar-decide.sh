#!/usr/bin/env bash
# ar-decide.sh — Mechanical decision engine for Ratchet
# Reads latest metrics + best metrics + guard result → outputs KEEP/DISCARD + reason
# This is NOT an LLM judgment — it's a deterministic script.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

root=$(ar_project_root)
state_path=$(ar_state_path)
latest_path="$root/.autoresearch/metrics/latest.json"

# Get guard result (passed as argument or run fresh)
guard_passed="${1:-true}"

python3 -c "
import json

with open('$state_path') as f:
    state = json.load(f)
best = state.get('best', {})

with open('$latest_path') as f:
    latest = json.load(f)

guard_ok = '$guard_passed'.lower() == 'true'

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

if not guard_ok:
    decision, reason = 'DISCARD', 'guard command failed'
elif worsened:
    decision, reason = 'DISCARD', 'metrics worsened'
elif improved:
    decision, reason = 'KEEP', 'metrics improved'
else:
    decision, reason = 'KEEP', 'metrics same (check code size for final judgment)'

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
" 2>/dev/null

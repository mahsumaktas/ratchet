#!/usr/bin/env bash
# ar-report.sh — Report generator for Ratchet
# Usage:
#   ar-report.sh checkpoint  — update CHECKPOINT.md
#   ar-report.sh summary     — generate SUMMARY.md
#   ar-report.sh progress    — one-line progress string

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

cmd="${1:-progress}"
root=$(ar_project_root)
ar_dir="$root/.autoresearch"

case "$cmd" in
  progress)
    AR_DIR_PATH="$ar_dir" python3 -c "
import json, os
with open(os.path.join(os.environ['AR_DIR_PATH'], 'state.json')) as f:
    s = json.load(f)
mode = s.get('mode', '?')
exp = s.get('experiment', 0)
kept = s.get('kept', 0)
disc = s.get('discarded', 0)
state = s.get('state', '?')
strategy = s.get('strategy', 'default')
total = kept + disc
pct = int(kept / total * 100) if total > 0 else 0
print(f'AR:{mode}#{exp} K:{kept}({pct}%) D:{disc} [{state}] strat:{strategy}')
" 2>/dev/null
    ;;

  summary)
    AR_DIR_PATH="$ar_dir" python3 -c "
import json, os
with open(os.path.join(os.environ['AR_DIR_PATH'], 'state.json')) as f:
    s = json.load(f)

baseline = s.get('baseline', {})
best = s.get('best', {})

lines = []
lines.append('# Ratchet Summary')
lines.append('')
lines.append(f\"**Project:** {s.get('project','?')} | **Mode:** {s.get('mode','?')} | **Branch:** {s.get('branch','?')}\")
lines.append(f\"**Started:** {s.get('start','?')}\")
lines.append('')
lines.append('## Metric Changes')
lines.append('| Metric | Start | End | Change |')
lines.append('|--------|-------|-----|--------|')
for key in ['test', 'lint', 'type', 'build']:
    b = baseline.get(key, '-')
    e = best.get(key, '-')
    try:
        change = int(e) - int(b)
        sign = '+' if change > 0 else ''
        lines.append(f'| {key} | {b} | {e} | {sign}{change} |')
    except (ValueError, TypeError):
        lines.append(f'| {key} | {b} | {e} | - |')

lines.append('')
kept = s.get('kept', 0)
disc = s.get('discarded', 0)
total = kept + disc
pct = int(kept / total * 100) if total > 0 else 0
lines.append('## Statistics')
lines.append(f'- Total experiments: {total}')
lines.append(f'- Kept: {kept} ({pct}%)')
lines.append(f'- Discarded: {disc}')
lines.append(f'- Strategy changes: (see decision log)')
lines.append('')
lines.append('## Discoveries')
for d in s.get('discoveries', []):
    lines.append(f'- {d}')
lines.append('')
lines.append('## Remaining Work')
lines.append('<!-- Large tasks the agent could not handle -->')

print('\n'.join(lines))
" > "$ar_dir/SUMMARY.md" 2>/dev/null
    echo "SUMMARY.md written to $ar_dir/SUMMARY.md" >&2
    ;;

  checkpoint)
    # Read current state and append progress
    exp=$(ar_state_get "experiment")
    state=$(ar_state_get "state")
    kept=$(ar_state_get "kept")
    discarded=$(ar_state_get "discarded")
    strategy=$(ar_state_get "strategy")

    progress_line="- Experiment $exp: state=$state, kept=$kept, discarded=$discarded, strategy=$strategy ($(date -u +%H:%M))"

    if [ -f "$ar_dir/CHECKPOINT.md" ]; then
      # Append to Progress section
      sed -i.bak "/^## Decision Log/i\\
$progress_line" "$ar_dir/CHECKPOINT.md" 2>/dev/null && rm -f "$ar_dir/CHECKPOINT.md.bak"
    fi
    echo "CHECKPOINT.md updated" >&2
    ;;

  *)
    echo "Usage: ar-report.sh {progress|summary|checkpoint}" >&2
    exit 1
    ;;
esac

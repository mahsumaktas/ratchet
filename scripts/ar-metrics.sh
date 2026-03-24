#!/usr/bin/env bash
# ar-metrics.sh — Frozen metric runner for Ratchet
# Usage:
#   ar-metrics.sh run      — run all frozen metrics, write latest.json
#   ar-metrics.sh compare  — compare latest vs best, output delta JSON

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

cmd="${1:-run}"
root=$(ar_project_root)
metrics_dir="$root/.autoresearch/metrics"
mkdir -p "$metrics_dir"

case "$cmd" in
  run)
    state_path=$(ar_state_path)
    frozen=$(python3 -c "
import json
with open('$state_path') as f:
    d = json.load(f)
fc = d.get('frozen_commands', {})
for k, v in fc.items():
    if k != 'guard' and v:
        print(f'{k}={v}')
" 2>/dev/null)

    results="{}"
    while IFS='=' read -r metric cmd_str; do
      [ -z "$metric" ] && continue
      result=$(cd "$root" && timeout 60 bash -c "$cmd_str" 2>/dev/null | tail -1 || echo "error")
      results=$(echo "$results" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['$metric'] = '''$result'''.strip()
print(json.dumps(d))
" 2>/dev/null)
    done <<< "$frozen"

    # Write latest
    echo "$results" > "$metrics_dir/latest.json"

    # Append to history
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"ts\":\"$ts\",\"metrics\":$results}" >> "$metrics_dir/history.jsonl"

    echo "$results"
    ;;

  compare)
    python3 -c "
import json

with open('$metrics_dir/latest.json') as f:
    latest = json.load(f)

state_path = '$(ar_state_path)'
with open(state_path) as f:
    best = json.load(f).get('best', {})

delta = {}
for key in set(list(latest.keys()) + list(best.keys())):
    l = latest.get(key, '')
    b = best.get(key, '')
    try:
        li = int(l)
        bi = int(b)
        delta[key] = {'previous': bi, 'current': li, 'change': li - bi}
    except (ValueError, TypeError):
        delta[key] = {'previous': str(b), 'current': str(l), 'change': 'N/A'}

print(json.dumps(delta, indent=2))
" 2>/dev/null
    ;;

  *)
    echo "Usage: ar-metrics.sh {run|compare}" >&2
    exit 1
    ;;
esac

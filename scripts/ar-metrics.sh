#!/usr/bin/env bash
# ar-metrics.sh — Frozen metric runner for Ratchet
# Usage: ar-metrics.sh run | ar-metrics.sh compare

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

cmd="${1:-run}"
root=$(ar_project_root)
metrics_dir="$root/.autoresearch/metrics"
mkdir -p "$metrics_dir"

case "$cmd" in
  run)
    state_path=$(ar_state_path)

    # Run all metrics and build results in a single python3 call
    AR_STATE="$state_path" AR_ROOT="$root" AR_METRICS_DIR="$metrics_dir" python3 -c "
import json, os, subprocess, datetime

with open(os.environ['AR_STATE']) as f:
    state = json.load(f)
fc = state.get('frozen_commands', {})
root = os.environ['AR_ROOT']

results = {}
for key, cmd in fc.items():
    if key == 'guard' or not cmd:
        continue
    try:
        proc = subprocess.run(['bash', '-c', cmd], capture_output=True, text=True,
                            timeout=60, cwd=root)
        output = proc.stdout.strip()
        result = output.split('\n')[-1] if output else 'error'
    except (subprocess.TimeoutExpired, Exception):
        result = 'error'
    results[key] = result

# Write latest
metrics_dir = os.environ['AR_METRICS_DIR']
with open(os.path.join(metrics_dir, 'latest.json'), 'w') as f:
    json.dump(results, f)

# Append to history
ts = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
with open(os.path.join(metrics_dir, 'history.jsonl'), 'a') as f:
    f.write(json.dumps({'ts': ts, 'metrics': results}) + '\n')

print(json.dumps(results))
" 2>/dev/null
    ;;

  compare)
    AR_LATEST="$metrics_dir/latest.json" AR_STATE="$(ar_state_path)" python3 -c "
import json, os

with open(os.environ['AR_LATEST']) as f:
    latest = json.load(f)
with open(os.environ['AR_STATE']) as f:
    best = json.load(f).get('best', {})

delta = {}
for key in set(list(latest.keys()) + list(best.keys())):
    l, b = latest.get(key, ''), best.get(key, '')
    try:
        li, bi = int(l), int(b)
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

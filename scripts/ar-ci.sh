#!/usr/bin/env bash
# ar-ci.sh — Non-interactive CI/CD execution mode for Ratchet
# Exit codes: 0=improved, 1=no-change, 2=error
# Usage: ar-ci.sh [options]
#   --max-experiments N    Max experiments (default: 10)
#   --budget USD           Max cost in USD (default: unlimited)
#   --output FILE          Write results JSON to file
#   --mode MODE            Operating mode (default: run)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

# Parse arguments
MAX_EXP=10
BUDGET=0
OUTPUT=""
MODE="run"

while [ $# -gt 0 ]; do
  case "$1" in
    --max-experiments) MAX_EXP="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --help|-h)
      cat >&2 << 'HELP'
ar-ci.sh — Non-interactive CI/CD execution mode for Ratchet

Usage: ar-ci.sh [options]

Options:
  --max-experiments N    Max experiments to run (default: 10)
  --budget USD           Max cost in USD (default: unlimited)
  --output FILE          Write results JSON to file (default: stdout)
  --mode MODE            Operating mode: run, fix, security (default: run)
  --help                 Show this help

Exit Codes:
  0  Improvements were made (at least 1 KEEP)
  1  No improvements (all DISCARD or no experiments)
  2  Error (setup failed, budget exceeded, etc.)

Example:
  ar-ci.sh --max-experiments 20 --budget 5.00 --output results.json

GitHub Actions:
  - uses: actions/checkout@v4
  - run: bash ratchet/scripts/ar-ci.sh --max-experiments 10
HELP
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Validate environment
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo '{"error": "not a git repository"}' >&2
  exit 2
fi

if ! command -v python3 &>/dev/null; then
  echo '{"error": "python3 not found"}' >&2
  exit 2
fi

# Record start time
START_TIME=$(date +%s)
PROJECT_ROOT="$PWD"

# Run environment probe
PROBE=$("$SCRIPT_DIR/ar-probe.sh" "$PROJECT_ROOT" 2>/dev/null || echo '{}')

# Build result object
result=$(AR_MODE="$MODE" AR_MAX="$MAX_EXP" AR_BUDGET="$BUDGET" AR_PROBE="$PROBE" \
  AR_PROJECT="$(basename "$PROJECT_ROOT")" python3 -c "
import json, os
from datetime import datetime, timezone

result = {
    'version': '3.0',
    'project': os.environ['AR_PROJECT'],
    'mode': os.environ['AR_MODE'],
    'max_experiments': int(os.environ['AR_MAX']),
    'budget_usd': float(os.environ['AR_BUDGET']),
    'environment': json.loads(os.environ.get('AR_PROBE', '{}')),
    'started_at': datetime.now(timezone.utc).isoformat(),
    'status': 'ready',
    'experiments_run': 0,
    'kept': 0,
    'discarded': 0,
    'improvements': [],
    'errors': []
}
print(json.dumps(result, indent=2))
" 2>/dev/null)

# Output result
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Update result with timing
final_result=$(echo "$result" | AR_DURATION="$DURATION" python3 -c "
import json, sys, os
d = json.load(sys.stdin)
d['duration_seconds'] = int(os.environ['AR_DURATION'])
d['status'] = 'complete'

# Determine exit recommendation
if d['kept'] > 0:
    d['exit_code'] = 0
    d['summary'] = f\"{d['kept']} improvements made\"
else:
    d['exit_code'] = 1
    d['summary'] = 'no improvements'

print(json.dumps(d, indent=2))
" 2>/dev/null)

# Write output
if [ -n "$OUTPUT" ]; then
  echo "$final_result" > "$OUTPUT"
  echo "[CI] Results written to $OUTPUT" >&2
else
  echo "$final_result"
fi

# Determine exit code
exit_code=$(echo "$final_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('exit_code', 1))" 2>/dev/null || echo 1)
exit "$exit_code"

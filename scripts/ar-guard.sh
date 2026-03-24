#!/usr/bin/env bash
# ar-guard.sh — Guard command runner for Ratchet
# Usage: ar-guard.sh run

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

root=$(ar_project_root)
guard_cmd=$(ar_state_get "frozen_commands.guard")

if [ -z "$guard_cmd" ]; then
  echo '{"passed": true, "output": "no guard configured", "duration_ms": 0}'
  exit 0
fi

start_s=$(date +%s)
output=$(cd "$root" && ar_timeout 120 bash -c "$guard_cmd" 2>&1) && passed=true || passed=false
end_s=$(date +%s)
duration_ms=$(( (end_s - start_s) * 1000 ))

# Build JSON safely using env vars
AR_PASSED="$passed" AR_OUTPUT="$output" AR_DURATION="$duration_ms" python3 -c "
import json, os
output = os.environ['AR_OUTPUT'][:500]  # truncate
print(json.dumps({
    'passed': os.environ['AR_PASSED'] == 'true',
    'output': output,
    'duration_ms': int(os.environ['AR_DURATION'])
}))
" 2>/dev/null

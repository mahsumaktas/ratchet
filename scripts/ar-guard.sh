#!/usr/bin/env bash
# ar-guard.sh — Guard command runner for Ratchet
# Usage: ar-guard.sh run
# Runs the guard command and outputs JSON result.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

root=$(ar_project_root)
guard_cmd=$(ar_state_get "frozen_commands.guard")

if [ -z "$guard_cmd" ]; then
  echo '{"passed": true, "output": "no guard configured", "duration_ms": 0}'
  exit 0
fi

start_ms=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null)
output=$(cd "$root" && timeout 120 bash -c "$guard_cmd" 2>&1) && passed=true || passed=false
end_ms=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null)
duration=$((end_ms - start_ms))

# Truncate output to 500 chars
output_short=$(echo "$output" | tail -20 | head -c 500)

python3 -c "
import json
print(json.dumps({
    'passed': $( [ \"$passed\" = true ] && echo 'True' || echo 'False' ),
    'output': '''$output_short''',
    'duration_ms': $duration
}))
" 2>/dev/null

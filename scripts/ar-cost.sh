#!/usr/bin/env bash
# ar-cost.sh — Token and cost tracking for Ratchet sessions
# Usage: ar-cost.sh record|total|check|reset [args]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

root="$(ar_project_root 2>/dev/null)" || root="$PWD"
COST_FILE="$root/.autoresearch/cost.json"

# Default pricing (per 1M tokens) — can be overridden via config
INPUT_PRICE=${AR_INPUT_PRICE:-3.00}
OUTPUT_PRICE=${AR_OUTPUT_PRICE:-15.00}
# Approximate: assume 60% input, 40% output
INPUT_RATIO=0.6
OUTPUT_RATIO=0.4

cmd="${1:-total}"
shift || true

_ensure_cost_file() {
  mkdir -p "$(dirname "$COST_FILE")"
  if [ ! -f "$COST_FILE" ]; then
    echo '{"session_tokens": 0, "total_cost_usd": 0.0, "experiments": 0, "iterations": []}' > "$COST_FILE"
  fi
}

case "$cmd" in
  record)
    tokens="${1:-0}"
    _ensure_cost_file

    AR_TOKENS="$tokens" AR_COST_FILE="$COST_FILE" \
    AR_INPUT_PRICE="$INPUT_PRICE" AR_OUTPUT_PRICE="$OUTPUT_PRICE" \
    AR_INPUT_RATIO="$INPUT_RATIO" AR_OUTPUT_RATIO="$OUTPUT_RATIO" \
    python3 -c "
import json, os
from datetime import datetime, timezone

cost_path = os.environ['AR_COST_FILE']
tokens = int(os.environ['AR_TOKENS'])
input_price = float(os.environ['AR_INPUT_PRICE'])
output_price = float(os.environ['AR_OUTPUT_PRICE'])
input_ratio = float(os.environ['AR_INPUT_RATIO'])
output_ratio = float(os.environ['AR_OUTPUT_RATIO'])

with open(cost_path) as f:
    data = json.load(f)

data['session_tokens'] += tokens
# Cost calculation
input_tokens = tokens * input_ratio
output_tokens = tokens * output_ratio
cost = (input_tokens * input_price / 1_000_000) + (output_tokens * output_price / 1_000_000)
data['total_cost_usd'] = round(data['total_cost_usd'] + cost, 4)
data['experiments'] += 1
data['iterations'].append({
    'ts': datetime.now(timezone.utc).isoformat(),
    'tokens': tokens,
    'cost_usd': round(cost, 4)
})
# Keep only last 100 iterations
data['iterations'] = data['iterations'][-100:]

with open(cost_path, 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
    ;;

  total)
    _ensure_cost_file
    AR_COST_FILE="$COST_FILE" python3 -c "
import json, os
with open(os.environ['AR_COST_FILE']) as f:
    d = json.load(f)
tokens = d.get('session_tokens', 0)
cost = d.get('total_cost_usd', 0)
exps = d.get('experiments', 0)
if tokens >= 1_000_000:
    t_str = f'{tokens/1_000_000:.1f}M'
elif tokens >= 1000:
    t_str = f'{tokens/1000:.0f}K'
else:
    t_str = str(tokens)
print(f'{t_str} tokens, ~\${cost:.2f}, {exps} experiments')
" 2>/dev/null
    ;;

  check)
    budget="${1:-0}"
    _ensure_cost_file
    AR_BUDGET="$budget" AR_COST_FILE="$COST_FILE" python3 -c "
import json, os, sys
with open(os.environ['AR_COST_FILE']) as f:
    d = json.load(f)
cost = d.get('total_cost_usd', 0)
budget = float(os.environ['AR_BUDGET'])
if budget > 0 and cost >= budget:
    print(f'BUDGET EXCEEDED: \${cost:.2f} >= \${budget:.2f}', file=sys.stderr)
    sys.exit(1)
print(f'OK: \${cost:.2f} / \${budget:.2f}')
" 2>/dev/null
    ;;

  reset)
    _ensure_cost_file
    echo '{"session_tokens": 0, "total_cost_usd": 0.0, "experiments": 0, "iterations": []}' > "$COST_FILE"
    echo "Cost tracking reset."
    ;;

  *)
    echo "Usage: ar-cost.sh record|total|check|reset [args]" >&2
    exit 1
    ;;
esac

#!/usr/bin/env bash
# ar-config.sh — Config reader and validator for Ratchet
# Usage:
#   ar-config.sh get <field>    — get config value (with defaults)
#   ar-config.sh validate       — validate config.json against schema
#   ar-config.sh defaults       — print default config

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

cmd="${1:-defaults}"

DEFAULT_CONFIG='{
  "mode": "run",
  "never_touch": ["*.lock", "node_modules/**", "vendor/**", ".env*", "*.min.js", "*.min.css", "dist/**", "build/**"],
  "guard_command": "",
  "parallel_workers": 1,
  "max_experiments": null,
  "notify_webhook": "",
  "consecutive_discard_limit": 5,
  "hard_stop_discard_limit": 10,
  "validator_interval": 5,
  "auto_checkpoint_interval": 3,
  "strategy_rotation": ["default", "low-hanging-fruit", "deep-refactor", "security-sweep", "dead-code-cleanup", "discovery-driven"]
}'

case "$cmd" in
  get)
    field="${2:?Usage: ar-config.sh get <field>}"
    val=$(ar_config_get "$field" "")
    if [ -n "$val" ]; then
      echo "$val"
    else
      echo "$DEFAULT_CONFIG" | AR_FIELD="$field" python3 -c "import json,sys,os; d=json.load(sys.stdin); print(d.get(os.environ['AR_FIELD'],''))" 2>/dev/null
    fi
    ;;

  validate)
    root=$(ar_project_root 2>/dev/null) || { echo "No project root found" >&2; exit 1; }
    config_path="$root/.autoresearch/config.json"

    if [ ! -f "$config_path" ]; then
      echo "No config.json found (using defaults)" >&2
      exit 0
    fi

    AR_CONFIG_PATH="$config_path" python3 -c "
import json, sys, os
try:
    with open(os.environ['AR_CONFIG_PATH']) as f:
        d = json.load(f)
    required_types = {
        'mode': str,
        'never_touch': list,
        'parallel_workers': int,
    }
    errors = []
    for field, expected in required_types.items():
        if field in d and not isinstance(d[field], expected):
            errors.append(f'{field}: expected {expected.__name__}, got {type(d[field]).__name__}')

    valid_modes = ['run', 'debug', 'fix', 'security', 'predict', 'plan']
    if 'mode' in d and d['mode'] not in valid_modes:
        errors.append(f\"mode: must be one of {valid_modes}\")

    if errors:
        print('INVALID:', '; '.join(errors))
        sys.exit(1)
    else:
        print('VALID')
except json.JSONDecodeError as e:
    print(f'INVALID JSON: {e}')
    sys.exit(1)
" 2>/dev/null
    ;;

  defaults)
    echo "$DEFAULT_CONFIG"
    ;;

  *)
    echo "Usage: ar-config.sh {get <field>|validate|defaults}" >&2
    exit 1
    ;;
esac

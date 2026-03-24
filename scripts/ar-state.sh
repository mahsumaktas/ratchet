#!/usr/bin/env bash
# ar-state.sh — State transition engine for Ratchet
# Usage:
#   ar-state.sh get                  — print current state
#   ar-state.sh transition <TARGET>  — validate and execute transition
#   ar-state.sh info                 — print full state summary

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

cmd="${1:-get}"

case "$cmd" in
  get)
    ar_state_get "state"
    ;;

  transition)
    target="${2:?Usage: ar-state.sh transition <TARGET_STATE>}"
    current=$(ar_state_get "state")

    if [ -z "$current" ]; then
      echo "ERROR: No active autoresearch session (state.json not found)" >&2
      exit 1
    fi

    if ar_validate_transition "$current" "$target"; then
      ar_state_set "state" "\"$target\""
      ar_log "info" "state" "transition" "from=$current" "to=$target"
      echo "$target"
    else
      echo "ERROR: Invalid transition $current -> $target" >&2
      ar_log "error" "state" "invalid-transition" "from=$current" "to=$target"
      exit 1
    fi
    ;;

  info)
    if ! ar_is_active 2>/dev/null && ! ar_project_root &>/dev/null; then
      echo "No active autoresearch session." >&2
      exit 1
    fi

    AR_STATE_FILE="$(ar_state_path)" python3 -c "
import json, os
with open(os.environ['AR_STATE_FILE']) as f:
    s = json.load(f)
print(f\"Mode:       {s.get('mode','?')}\")
print(f\"State:      {s.get('state','?')}\")
print(f\"Experiment: {s.get('experiment',0)}\")
print(f\"Kept:       {s.get('kept',0)}\")
print(f\"Discarded:  {s.get('discarded',0)}\")
print(f\"Consec.D:   {s.get('consecutive_discards',0)}\")
print(f\"Strategy:   {s.get('strategy','default')}\")
print(f\"Branch:     {s.get('branch','?')}\")
best = s.get('best', {})
print(f\"Best:       tests={best.get('tests','?')} lint={best.get('lint','?')} types={best.get('types','?')} build={best.get('build','?')}\")
" 2>/dev/null
    ;;

  *)
    echo "Usage: ar-state.sh {get|transition <STATE>|info}" >&2
    exit 1
    ;;
esac

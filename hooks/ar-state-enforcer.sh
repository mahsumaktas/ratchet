#!/usr/bin/env bash
# ar-state-enforcer.sh — PreToolUse hook: blocks invalid state transitions
# Matcher: Write|Edit|MultiEdit|Bash
# Exit 2 = HARD BLOCK, Exit 0 = allow, systemMessage = soft warning
set -euo pipefail

# Fast exit if autoresearch not active (<1ms)
[ -f "/tmp/ar-active-${PPID}.txt" ] || exit 0

# Source library AFTER fast exit check
SCRIPT_DIR="${HOME}/.claude/skills/autoresearch/scripts"
[ -f "$SCRIPT_DIR/_lib.sh" ] || exit 0
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Parse all fields from hook input in a single python3 call
INPUT=$(cat)
ar_parse_hook_input "$INPUT"

# Get project root and state
ROOT=$(cat "$AR_ROOT_CACHE" 2>/dev/null) || exit 0
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

CURRENT_STATE=$(ar_state_get "state")
[ -n "$CURRENT_STATE" ] || exit 0

# --- Handle Write/Edit/MultiEdit ---
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "MultiEdit" ]]; then
  # Always allow edits to .autoresearch/ files
  [[ "$FILE_PATH" == *".autoresearch/"* ]] && exit 0

  # Only allow project code edits in MAKE_CHANGE state
  if [ "$CURRENT_STATE" != "MAKE_CHANGE" ]; then
    ar_emit "[RATCHET STATE] Current state is $CURRENT_STATE — edits to project code only allowed in MAKE_CHANGE state. Run ar-state.sh transition MAKE_CHANGE first."
  fi
  exit 0
fi

# --- Handle Bash (git commit enforcement) ---
if [ "$TOOL_NAME" = "Bash" ]; then
  # Block git commit outside COMMIT state
  if [[ "$COMMAND" == *"git commit"* ]]; then
    if [ "$CURRENT_STATE" != "COMMIT" ]; then
      echo "ENGELLENDI: git commit only allowed in COMMIT state. Current: $CURRENT_STATE" >&2
      ar_log "warn" "state-enforcer" "blocked" "tool=$TOOL_NAME" "state=$CURRENT_STATE"
      exit 2
    fi
  fi

  # Warn git revert outside REVERT state
  if [[ "$COMMAND" == *"git checkout -- "* || "$COMMAND" == *"git restore "* ]]; then
    if [ "$CURRENT_STATE" != "REVERT" ]; then
      ar_emit "[RATCHET STATE] git revert only in REVERT state. Current: $CURRENT_STATE. Run ar-state.sh transition REVERT first."
    fi
  fi
fi

ar_log "debug" "state-enforcer" "allowed" "tool=$TOOL_NAME"

exit 0

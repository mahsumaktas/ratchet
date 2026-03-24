#!/usr/bin/env bash
# ar-state-enforcer.sh — PreToolUse hook: blocks invalid state transitions
# Matcher: Write|Edit|MultiEdit|Bash
# Exit 2 = HARD BLOCK, Exit 0 = allow, systemMessage = soft warning

AR_ACTIVE_FLAG="/tmp/ar-active-${PPID}.txt"
AR_ROOT_CACHE="/tmp/ar-root-${PPID}.txt"

# Fast exit if autoresearch not active (<1ms)
[ -f "$AR_ACTIVE_FLAG" ] || exit 0

# Read tool input
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Get project root and state
ROOT=$(cat "$AR_ROOT_CACHE" 2>/dev/null || exit 0)
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

CURRENT_STATE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('state',''))" 2>/dev/null)
[ -n "$CURRENT_STATE" ] || exit 0

# --- Handle Write/Edit/MultiEdit ---
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "MultiEdit" ]]; then
  FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

  # Always allow edits to .autoresearch/ files (state updates, checkpoint writes)
  if [[ "$FILE_PATH" == *".autoresearch/"* ]]; then
    exit 0
  fi

  # Only allow project code edits in MAKE_CHANGE state
  if [ "$CURRENT_STATE" != "MAKE_CHANGE" ]; then
    python3 -c "
import json
msg = '[RATCHET STATE] Current state is $CURRENT_STATE — edits to project code only allowed in MAKE_CHANGE state. Run ar-state.sh transition MAKE_CHANGE first.'
print(json.dumps({'systemMessage': msg}))
" 2>/dev/null
  fi
  exit 0
fi

# --- Handle Bash (git commit enforcement) ---
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

  # Block git commit outside COMMIT state
  if echo "$COMMAND" | grep -q 'git commit'; then
    if [ "$CURRENT_STATE" != "COMMIT" ]; then
      echo "ENGELLENDI: git commit only allowed in COMMIT state. Current: $CURRENT_STATE" >&2
      exit 2
    fi
  fi

  # Block git checkout -- (revert) outside REVERT state
  if echo "$COMMAND" | grep -qE 'git checkout -- |git restore '; then
    if [ "$CURRENT_STATE" != "REVERT" ]; then
      python3 -c "
import json
msg = '[RATCHET STATE] git revert only in REVERT state. Current: $CURRENT_STATE. Run ar-state.sh transition REVERT first.'
print(json.dumps({'systemMessage': msg}))
" 2>/dev/null
    fi
  fi
fi

exit 0

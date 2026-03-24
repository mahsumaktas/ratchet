#!/usr/bin/env bash
# ar-boundary-guard.sh — PreToolUse hook: blocks edits to never_touch files
# Matcher: Write|Edit|MultiEdit
# Exit 2 = HARD BLOCK when file matches never_touch glob

# Fast exit if autoresearch not active
[ -f "/tmp/ar-active-${PPID}.txt" ] || exit 0

SCRIPT_DIR="${HOME}/.claude/skills/autoresearch/scripts"
[ -f "$SCRIPT_DIR/_lib.sh" ] || exit 0
source "$SCRIPT_DIR/_lib.sh"

INPUT=$(cat)
ar_parse_hook_input "$INPUT"
[ -n "$FILE_PATH" ] || exit 0

# Always allow .autoresearch/ edits
[[ "$FILE_PATH" == *".autoresearch/"* ]] && exit 0

ROOT=$(cat "$AR_ROOT_CACHE" 2>/dev/null) || exit 0
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

# Make file path relative to project root
REL_PATH="${FILE_PATH#$ROOT/}"

# Check ALL patterns in a single python3 call (not one per pattern)
matched_pattern=$(ar_check_boundary "$REL_PATH" "$STATE_FILE")

if [ -n "$matched_pattern" ]; then
  echo "ENGELLENDI: '$REL_PATH' matches never_touch pattern '$matched_pattern'" >&2
  exit 2
fi

exit 0

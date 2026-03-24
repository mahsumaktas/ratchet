#!/usr/bin/env bash
# ar-boundary-guard.sh — PreToolUse hook: blocks edits to never_touch files
# Matcher: Write|Edit|MultiEdit
# Exit 2 = HARD BLOCK when file matches never_touch glob

AR_ACTIVE_FLAG="/tmp/ar-active-${PPID}.txt"
AR_ROOT_CACHE="/tmp/ar-root-${PPID}.txt"

# Fast exit if autoresearch not active
[ -f "$AR_ACTIVE_FLAG" ] || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -n "$FILE_PATH" ] || exit 0

# Always allow .autoresearch/ edits
[[ "$FILE_PATH" == *".autoresearch/"* ]] && exit 0

ROOT=$(cat "$AR_ROOT_CACHE" 2>/dev/null || exit 0)
STATE_FILE="$ROOT/.autoresearch/state.json"
[ -f "$STATE_FILE" ] || exit 0

# Get never_touch patterns (cached in /tmp for performance)
NEVER_TOUCH_CACHE="/tmp/ar-never-touch-${PPID}.txt"
if [ ! -f "$NEVER_TOUCH_CACHE" ]; then
  python3 -c "
import json
with open('$STATE_FILE') as f:
    patterns = json.load(f).get('never_touch', [])
for p in patterns:
    print(p)
" > "$NEVER_TOUCH_CACHE" 2>/dev/null
fi

# Make file path relative to project root
REL_PATH="${FILE_PATH#$ROOT/}"

# Check each pattern
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue

  # Use python fnmatch for glob matching
  match=$(python3 -c "
import fnmatch
print('yes' if fnmatch.fnmatch('$REL_PATH', '$pattern') else 'no')
" 2>/dev/null)

  if [ "$match" = "yes" ]; then
    echo "ENGELLENDI: '$REL_PATH' matches never_touch pattern '$pattern'" >&2
    exit 2
  fi
done < "$NEVER_TOUCH_CACHE"

exit 0

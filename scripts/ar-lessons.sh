#!/usr/bin/env bash
# ar-lessons.sh — Cross-run lessons with 50-entry cap and 30-day time-decay
# Usage: ar-lessons.sh read|add|prune [args]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

root="$(ar_project_root 2>/dev/null)" || root="$PWD"
LESSONS_FILE="$root/.autoresearch/lessons.jsonl"

cmd="${1:-read}"
shift || true

case "$cmd" in
  add)
    lesson_text="$*"
    [ -z "$lesson_text" ] && exit 0
    mkdir -p "$(dirname "$LESSONS_FILE")"

    AR_LESSON="$lesson_text" python3 -c "
import json, os
from datetime import datetime, timezone

entry = {
    'ts': datetime.now(timezone.utc).isoformat(),
    'lesson': os.environ['AR_LESSON']
}
print(json.dumps(entry, ensure_ascii=False))
" >> "$LESSONS_FILE"

    # Cap at 50 entries — remove oldest if over
    if [ -f "$LESSONS_FILE" ]; then
      line_count=$(wc -l < "$LESSONS_FILE")
      if [ "$line_count" -gt 50 ]; then
        tail -50 "$LESSONS_FILE" > "$LESSONS_FILE.tmp"
        mv "$LESSONS_FILE.tmp" "$LESSONS_FILE"
      fi
    fi
    ;;

  read)
    [ -f "$LESSONS_FILE" ] || exit 0
    python3 -c "
import json, sys
lessons = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        lessons.append(d.get('lesson', ''))
    except: continue
for i, l in enumerate(lessons[-20:], 1):
    print(f'{i}. {l}')
" "$LESSONS_FILE" 2>/dev/null
    ;;

  prune)
    [ -f "$LESSONS_FILE" ] || exit 0
    python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta

cutoff = datetime.now(timezone.utc) - timedelta(days=30)
kept = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        ts = datetime.fromisoformat(d['ts'])
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        if ts > cutoff:
            kept.append(line)
    except:
        kept.append(line)

with open(sys.argv[1], 'w') as f:
    f.write('\n'.join(kept) + '\n' if kept else '')
print(f'Pruned: kept {len(kept)} lessons')
" "$LESSONS_FILE" 2>/dev/null
    ;;

  *)
    echo "Usage: ar-lessons.sh read|add|prune [args]" >&2
    exit 1
    ;;
esac

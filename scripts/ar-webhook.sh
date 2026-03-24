#!/usr/bin/env bash
# ar-webhook.sh — Notification dispatcher for Ratchet
# Usage: ar-webhook.sh <event> [message]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

event="${1:-info}"
message="${2:-}"

webhook_url=$(ar_config_get "notify_webhook" "")
[ -n "$webhook_url" ] || exit 0

root=$(ar_project_root 2>/dev/null) || root="unknown"
project=$(basename "$root")
progress=$("$SCRIPT_DIR/ar-report.sh" progress 2>/dev/null || echo "?")

# Build JSON payload safely
AR_EVENT="$event" AR_MSG="$message" AR_PROJECT="$project" AR_PROGRESS="$progress" python3 -c "
import json, os
payload = json.dumps({
    'text': f'[ratchet] {os.environ[\"AR_EVENT\"]}: {os.environ[\"AR_MSG\"]}',
    'blocks': [{
        'type': 'section',
        'text': {
            'type': 'mrkdwn',
            'text': (f'*Ratchet* | {os.environ[\"AR_PROJECT\"]}\n'
                    f'*Event:* {os.environ[\"AR_EVENT\"]}\n'
                    f'*Progress:* {os.environ[\"AR_PROGRESS\"]}\n'
                    f'{os.environ[\"AR_MSG\"]}')
        }
    }]
})
print(payload)
" 2>/dev/null | curl -s -X POST -H 'Content-Type: application/json' \
  -d @- "$webhook_url" --max-time 5 >/dev/null 2>&1 || true

ar_log "info" "webhook sent: event=$event"

#!/usr/bin/env bash
# ar-webhook.sh — Notification dispatcher for Ratchet
# Usage: ar-webhook.sh <event> [message]
# Events: start, experiment, strategy_change, alert, complete

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

event="${1:-info}"
message="${2:-}"

# Get webhook URL from config
webhook_url=$(ar_config_get "notify_webhook" "")

if [ -z "$webhook_url" ]; then
  exit 0  # No webhook configured, silently exit
fi

# Build payload
root=$(ar_project_root 2>/dev/null) || root="unknown"
project=$(basename "$root")
progress=$("$SCRIPT_DIR/ar-report.sh" progress 2>/dev/null || echo "?")

payload=$(python3 -c "
import json
print(json.dumps({
    'text': f'[ratchet] {\"$event\"}: {\"$message\"}',
    'blocks': [
        {'type': 'section', 'text': {'type': 'mrkdwn', 'text': f'*Ratchet* | {\"$project\"}\n*Event:* {\"$event\"}\n*Progress:* {\"$progress\"}\n{\"$message\"}'}}
    ]
}))
" 2>/dev/null)

# Send notification (non-blocking, don't fail if webhook is down)
curl -s -X POST -H 'Content-Type: application/json' \
  -d "$payload" \
  "$webhook_url" \
  --max-time 5 \
  >/dev/null 2>&1 || true

ar_log "info" "webhook sent: event=$event"

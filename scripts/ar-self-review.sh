#!/usr/bin/env bash
# ar-self-review.sh — Autonomous self-review engine
# Analyzes experiments.jsonl, detects patterns, auto-adjusts config
# Usage: ar-self-review.sh [trigger]
# trigger: "session_end" | "threshold" | "manual"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

[ -f "/tmp/ar-active-${PPID}.txt" ] || exit 0

trigger="${1:-manual}"
root="$(ar_project_root 2>/dev/null)" || exit 0
log_dir="$root/.autoresearch/logs"
config_file="$root/.autoresearch/config.json"
experiments_file="$log_dir/experiments.jsonl"
insights_file="$log_dir/insights.jsonl"
checkpoint_file="$root/.autoresearch/CHECKPOINT.md"

# Skip if no experiments data
[ -f "$experiments_file" ] && [ -s "$experiments_file" ] || exit 0

# Config backup
if [ -f "$config_file" ]; then
  cp "$config_file" "$config_file.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
fi

# Run Python engine
AR_TRIGGER="$trigger" \
AR_EXPERIMENTS="$experiments_file" \
AR_CONFIG="$config_file" \
AR_INSIGHTS="$insights_file" \
AR_CHECKPOINT="$checkpoint_file" \
AR_ROOT="$root" \
  python3 "$SCRIPT_DIR/ar-self-review-engine.py" 2>/dev/null || true

ar_log "info" "self-review" "completed" "trigger=$trigger"

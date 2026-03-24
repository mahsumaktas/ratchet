#!/usr/bin/env bash
# _lib.sh — Ratchet shared library
# Sourced by all ar-* scripts. Provides state management, locking, and transition validation.

set -euo pipefail

# --- Constants ---
AR_STATE_FILE_NAME=".autoresearch/state.json"
AR_CONFIG_FILE_NAME=".autoresearch/config.json"
AR_ACTIVE_FLAG="/tmp/ar-active-${PPID}.txt"
AR_ROOT_CACHE="/tmp/ar-root-${PPID}.txt"
AR_LOG_FILE="${HOME}/.claude/logs/autoresearch.jsonl"

# --- Valid State Transitions ---
# Format: "FROM:TO" — only these transitions are allowed
VALID_TRANSITIONS=(
  "BOOTSTRAP:SELECT_TARGET"
  "SELECT_TARGET:READ_FILE"
  "SELECT_TARGET:STOP"
  "READ_FILE:MAKE_CHANGE"
  "READ_FILE:SELECT_TARGET"
  "MAKE_CHANGE:VALIDATE"
  "MAKE_CHANGE:REVERT"
  "VALIDATE:DECIDE"
  "DECIDE:COMMIT"
  "DECIDE:REVERT"
  "COMMIT:LOG"
  "REVERT:LOG"
  "LOG:SELECT_TARGET"
  "LOG:STRATEGY_CHANGE"
  "LOG:STOP"
  "STRATEGY_CHANGE:SELECT_TARGET"
  "STRATEGY_CHANGE:STOP"
)

# --- Fast Active Check ---
# Returns 0 if autoresearch session is active, 1 otherwise.
# Uses /tmp flag file for <1ms performance.
ar_is_active() {
  [ -f "$AR_ACTIVE_FLAG" ]
}

# --- Project Root Detection ---
# Walks up from $PWD looking for .autoresearch/state.json
# Caches result in /tmp for performance.
ar_project_root() {
  if [ -f "$AR_ROOT_CACHE" ]; then
    cat "$AR_ROOT_CACHE"
    return 0
  fi

  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/$AR_STATE_FILE_NAME" ]; then
      echo "$dir" > "$AR_ROOT_CACHE"
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  return 1
}

# --- State File Path ---
ar_state_path() {
  local root
  root=$(ar_project_root) || return 1
  echo "$root/$AR_STATE_FILE_NAME"
}

# --- Read State JSON ---
ar_state_read() {
  local path
  path=$(ar_state_path) || return 1
  cat "$path"
}

# --- Get Single Field from State ---
ar_state_get() {
  local field="$1"
  local path
  path=$(ar_state_path) || return 1
  python3 -c "
import json, sys
with open('$path') as f:
    d = json.load(f)
keys = '$field'.split('.')
val = d
for k in keys:
    val = val.get(k, '') if isinstance(val, dict) else ''
print(val if val != '' else '')
" 2>/dev/null
}

# --- Atomic State Write ---
# Uses tmp file + mv for crash safety.
ar_state_write() {
  local json_str="$1"
  local path
  path=$(ar_state_path) || return 1
  local tmp_file="${path}.tmp.$$"
  echo "$json_str" > "$tmp_file"
  mv "$tmp_file" "$path"
}

# --- Update Single Field in State ---
ar_state_set() {
  local field="$1"
  local value="$2"
  local path
  path=$(ar_state_path) || return 1

  python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
d['$field'] = $value
tmp = '$path.tmp.$$'
with open(tmp, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
import os
os.rename(tmp, '$path')
" 2>/dev/null
}

# --- Validate State Transition ---
# Returns 0 if valid, 1 if invalid.
ar_validate_transition() {
  local from="$1"
  local to="$2"
  local key="${from}:${to}"

  for valid in "${VALID_TRANSITIONS[@]}"; do
    if [ "$valid" = "$key" ]; then
      return 0
    fi
  done

  return 1
}

# --- Log to JSONL ---
ar_log() {
  local level="$1"
  local msg="$2"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p "$(dirname "$AR_LOG_FILE")"
  echo "{\"ts\":\"$ts\",\"level\":\"$level\",\"msg\":\"$msg\"}" >> "$AR_LOG_FILE"
}

# --- Emit System Message (stdout JSON) ---
ar_emit() {
  local msg="$1"
  python3 -c "
import json
print(json.dumps({'systemMessage': '''$msg'''}))" 2>/dev/null
}

# --- Config Read ---
ar_config_get() {
  local field="$1"
  local default="${2:-}"
  local root
  root=$(ar_project_root 2>/dev/null) || { echo "$default"; return 0; }
  local config_path="$root/$AR_CONFIG_FILE_NAME"

  if [ -f "$config_path" ]; then
    local val
    val=$(python3 -c "
import json
with open('$config_path') as f:
    d = json.load(f)
v = d.get('$field', None)
if v is not None:
    if isinstance(v, list):
        print(' '.join(v))
    else:
        print(v)
" 2>/dev/null)
    if [ -n "$val" ]; then
      echo "$val"
      return 0
    fi
  fi

  echo "$default"
}

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

# --- Portable timeout (macOS has no coreutils timeout by default) ---
ar_timeout() {
  local secs="$1"; shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
  else
    # Fallback: run without timeout
    "$@"
  fi
}

# --- Fast Active Check ---
ar_is_active() {
  [ -f "$AR_ACTIVE_FLAG" ]
}

# --- Project Root Detection ---
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

# --- Get Single Field from State (safe: uses env vars, not interpolation) ---
ar_state_get() {
  local field="$1"
  local path
  path=$(ar_state_path) || return 1
  AR_FIELD="$field" AR_PATH="$path" python3 -c "
import json, os
with open(os.environ['AR_PATH']) as f:
    d = json.load(f)
keys = os.environ['AR_FIELD'].split('.')
val = d
for k in keys:
    val = val.get(k, '') if isinstance(val, dict) else ''
print(val if val != '' else '')
" 2>/dev/null
}

# --- Get Multiple Fields from State (single python3 call) ---
ar_state_get_multi() {
  # Usage: ar_state_get_multi field1 field2 field3 ...
  # Outputs: field1=value1\nfield2=value2\n...
  local path
  path=$(ar_state_path) || return 1
  AR_PATH="$path" AR_FIELDS="$*" python3 -c "
import json, os
with open(os.environ['AR_PATH']) as f:
    d = json.load(f)
for field in os.environ['AR_FIELDS'].split():
    keys = field.split('.')
    val = d
    for k in keys:
        val = val.get(k, '') if isinstance(val, dict) else ''
    print(f'{field}={val}')
" 2>/dev/null
}

# --- Atomic State Write (safe: uses env var for JSON content) ---
ar_state_write() {
  local json_str="$1"
  local path
  path=$(ar_state_path) || return 1
  local tmp_file="${path}.tmp.$$"
  # Validate JSON before writing
  if ! echo "$json_str" | python3 -m json.tool > "$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file"
    echo "ERROR: Invalid JSON, refusing to write" >&2
    return 1
  fi
  mv "$tmp_file" "$path"
}

# --- Update Single Field in State (safe: uses env vars) ---
ar_state_set() {
  local field="$1"
  local value="$2"
  local path
  path=$(ar_state_path) || return 1
  AR_PATH="$path" AR_FIELD="$field" AR_VALUE="$value" python3 -c "
import json, os
path = os.environ['AR_PATH']
field = os.environ['AR_FIELD']
value_str = os.environ['AR_VALUE']
with open(path) as f:
    d = json.load(f)
# Parse the value as JSON (handles strings, numbers, booleans, null)
try:
    value = json.loads(value_str)
except json.JSONDecodeError:
    value = value_str
d[field] = value
tmp = path + '.tmp.' + str(os.getpid())
with open(tmp, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
os.rename(tmp, path)
" 2>/dev/null
}

# --- Validate State Transition ---
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

# --- Log to JSONL (safe: uses python3 for proper JSON escaping) ---
ar_log() {
  local level="$1"
  local msg="$2"
  mkdir -p "$(dirname "$AR_LOG_FILE")"
  AR_LEVEL="$level" AR_MSG="$msg" python3 -c "
import json, os, datetime
entry = {
    'ts': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'level': os.environ['AR_LEVEL'],
    'msg': os.environ['AR_MSG']
}
with open(os.environ.get('AR_LOG_FILE', os.path.expanduser('~/.claude/logs/autoresearch.jsonl')), 'a') as f:
    f.write(json.dumps(entry) + '\n')
" 2>/dev/null || true
}

# --- Emit System Message (safe: uses env var) ---
ar_emit() {
  local msg="$1"
  AR_MSG="$msg" python3 -c "
import json, os
print(json.dumps({'systemMessage': os.environ['AR_MSG']}))
" 2>/dev/null
}

# --- Parse Hook Input (single python3 call for all fields) ---
# Sets: TOOL_NAME, FILE_PATH, COMMAND via eval
ar_parse_hook_input() {
  local input="$1"
  eval "$(echo "$input" | python3 -c "
import json, sys, shlex
d = json.load(sys.stdin)
tn = d.get('tool_name', '')
ti = d.get('tool_input', {})
fp = ti.get('file_path', '')
cmd = ti.get('command', '')
# Use shlex.quote to prevent injection
print(f'TOOL_NAME={shlex.quote(tn)}')
print(f'FILE_PATH={shlex.quote(fp)}')
print(f'COMMAND={shlex.quote(cmd)}')
" 2>/dev/null)" 2>/dev/null || {
    TOOL_NAME=""
    FILE_PATH=""
    COMMAND=""
  }
}

# --- Config Read (safe: uses env vars) ---
ar_config_get() {
  local field="$1"
  local default="${2:-}"
  local root
  root=$(ar_project_root 2>/dev/null) || { echo "$default"; return 0; }
  local config_path="$root/$AR_CONFIG_FILE_NAME"
  if [ -f "$config_path" ]; then
    local val
    val=$(AR_FIELD="$field" AR_CONFIG="$config_path" python3 -c "
import json, os
with open(os.environ['AR_CONFIG']) as f:
    d = json.load(f)
v = d.get(os.environ['AR_FIELD'], None)
if v is not None:
    if isinstance(v, list):
        print(' '.join(str(x) for x in v))
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

# --- Check all never_touch patterns in a single call ---
ar_check_boundary() {
  local file_path="$1"
  local state_file="$2"
  AR_FILE="$file_path" AR_STATE="$state_file" python3 -c "
import json, os, fnmatch
with open(os.environ['AR_STATE']) as f:
    patterns = json.load(f).get('never_touch', [])
fp = os.environ['AR_FILE']
for p in patterns:
    if fnmatch.fnmatch(fp, p):
        print(p)
        exit(0)
print('')
" 2>/dev/null
}

# --- Cleanup tmp files for this session ---
ar_cleanup() {
  rm -f "/tmp/ar-active-${PPID}.txt" \
        "/tmp/ar-root-${PPID}.txt" \
        "/tmp/ar-never-touch-${PPID}.txt" \
        "/tmp/ar-state-${PPID}.txt" 2>/dev/null || true
}

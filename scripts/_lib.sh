#!/usr/bin/env bash
# _lib.sh — Ratchet shared library
# Sourced by all ar-* scripts. Provides state management, locking, and transition validation.

set -euo pipefail

# --- Constants ---
AR_STATE_FILE_NAME=".autoresearch/state.json"
AR_CONFIG_FILE_NAME=".autoresearch/config.json"
AR_ACTIVE_FLAG="/tmp/ar-active-${PPID}.txt"
AR_ROOT_CACHE="/tmp/ar-root-${PPID}.txt"
AR_LOG_FILE="${HOME}/.claude/logs/autoresearch.jsonl"  # Legacy, kept for backward compat

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

# --- Log to project-local JSONL (safe: key=value pairs, no JSON injection) ---
ar_log() {
  # Usage: ar_log level hook event [key=value ...]
  local level="$1" hook="$2" event="$3"
  shift 3

  local root
  root="$(ar_project_root 2>/dev/null)" || return 0
  local log_dir="$root/.autoresearch/logs"
  mkdir -p "$log_dir" 2>/dev/null || return 0

  # Log rotation: events.jsonl > 5MB
  local log_file="$log_dir/events.jsonl"
  local file_size
  file_size=$(stat -c %s "$log_file" 2>/dev/null || echo 0)
  if [ "$file_size" -gt 5242880 ] 2>/dev/null; then
    mv -f "$log_file.2" "$log_file.3" 2>/dev/null
    mv -f "$log_file.1" "$log_file.2" 2>/dev/null
    mv -f "$log_file" "$log_file.1" 2>/dev/null
  fi

  # Key=value pairs via safe export
  local i=0
  for kv in "$@"; do
    export "AR_KV_${i}=${kv}"
    i=$((i + 1))
  done
  export AR_KV_COUNT="$i"

  AR_LEVEL="$level" AR_HOOK="$hook" AR_EVENT="$event" \
    python3 -c "
import json, os
from datetime import datetime, timezone
entry = {
    'ts': datetime.now(timezone.utc).isoformat(),
    'level': os.environ['AR_LEVEL'],
    'hook': os.environ['AR_HOOK'],
    'event': os.environ['AR_EVENT'],
}
count = int(os.environ.get('AR_KV_COUNT', '0'))
for i in range(count):
    kv = os.environ.get(f'AR_KV_{i}', '')
    if '=' in kv:
        k, v = kv.split('=', 1)
        entry[k] = v
print(json.dumps(entry, ensure_ascii=False))
" >> "$log_file" 2>/dev/null

  # Cleanup exported env vars
  for j in $(seq 0 $((i - 1))); do unset "AR_KV_${j}"; done
  unset AR_KV_COUNT
}

# --- Log experiment result to experiments.jsonl ---
ar_log_experiment() {
  local root
  root="$(ar_project_root 2>/dev/null)" || return 0
  local log_dir="$root/.autoresearch/logs"
  mkdir -p "$log_dir" 2>/dev/null || return 0

  python3 -c "
import json, os
from datetime import datetime, timezone

def safe_json(s):
    try: return json.loads(s)
    except: return s

entry = {
    'ts': datetime.now(timezone.utc).isoformat(),
    'experiment_id': int(os.environ.get('AR_EXP_ID', '0') or '0'),
    'strategy': os.environ.get('AR_STRATEGY', ''),
    'target_file': os.environ.get('AR_TARGET_FILE', ''),
    'diff_summary': os.environ.get('AR_DIFF_SUMMARY', ''),
    'metrics_before': safe_json(os.environ.get('AR_METRICS_BEFORE', '{}')),
    'metrics_after': safe_json(os.environ.get('AR_METRICS_AFTER', '{}')),
    'guard_passed': os.environ.get('AR_GUARD_PASSED', 'true') == 'true',
    'decision': os.environ.get('AR_DECISION', ''),
    'reason': os.environ.get('AR_REASON', ''),
    'duration_sec': float(os.environ.get('AR_DURATION_SEC', '0') or '0'),
}
print(json.dumps(entry, ensure_ascii=False))
" >> "$log_dir/experiments.jsonl" 2>/dev/null
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
# Custom glob matcher: supports ** recursive, * single-segment, fnmatch basics
ar_check_boundary() {
  local file_path="$1"
  local state_file="$2"
  AR_FILE="$file_path" AR_STATE="$state_file" python3 -c "
import json, os, fnmatch

def glob_match(filepath, pattern):
    \"\"\"Match filepath against glob pattern with ** support.\"\"\"
    if '**' in pattern:
        parts = pattern.split('**', 1)
        prefix = parts[0].rstrip('/')
        suffix = parts[1].lstrip('/') if parts[1] else ''
        # Check prefix matches
        if prefix:
            if not (filepath.startswith(prefix + '/') or filepath == prefix):
                return False
            remainder = filepath[len(prefix)+1:]
        else:
            remainder = filepath
        # No suffix means match everything under prefix
        if not suffix:
            return True
        # Check suffix against all possible sub-paths
        segs = remainder.split('/')
        for i in range(len(segs)):
            if fnmatch.fnmatch('/'.join(segs[i:]), suffix):
                return True
        return False
    return fnmatch.fnmatch(filepath, pattern)

with open(os.environ['AR_STATE']) as f:
    patterns = json.load(f).get('never_touch', [])
fp = os.environ['AR_FILE']
for p in patterns:
    if glob_match(fp, p):
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

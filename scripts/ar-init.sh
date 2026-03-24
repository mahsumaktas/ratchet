#!/usr/bin/env bash
# ar-init.sh — Bootstrap a new Ratchet autoresearch session
# Usage: ar-init.sh [mode] [max_experiments]
# Modes: run (default), debug, fix, security, predict, plan

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

MODE="${1:-run}"
MAX_EXPERIMENTS="${2:-null}"
PROJECT_ROOT="$PWD"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BRANCH="autoresearch/$TIMESTAMP"
AR_DIR="$PROJECT_ROOT/.autoresearch"

# --- Pre-checks ---
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "ERROR: Not a git repository. Ratchet requires git." >&2
  exit 1
fi

if [ -f "$AR_DIR/state.json" ]; then
  state=$(python3 -c "import json; print(json.load(open('$AR_DIR/state.json')).get('state',''))" 2>/dev/null)
  if [ "$state" != "STOP" ] && [ -n "$state" ]; then
    echo "WARNING: Active session found (state=$state). Use ar-state.sh to manage." >&2
    echo "To force restart, delete $AR_DIR/state.json first." >&2
    exit 1
  fi
fi

# --- Detect project type ---
detect_commands() {
  local test_cmd="" lint_cmd="" type_cmd="" build_cmd=""

  if [ -f "$PROJECT_ROOT/package.json" ]; then
    # Node.js project
    local scripts
    scripts=$(python3 -c "import json; s=json.load(open('$PROJECT_ROOT/package.json')).get('scripts',{}); print(' '.join(s.keys()))" 2>/dev/null || echo "")

    [[ "$scripts" == *"test"* ]] && test_cmd="npm test 2>&1"
    [[ "$scripts" == *"lint"* ]] && lint_cmd="npm run lint 2>&1 | wc -l"

    if [ -f "$PROJECT_ROOT/tsconfig.json" ]; then
      type_cmd="npx tsc --noEmit 2>&1 | grep -c 'error TS' || true"
    fi

    [[ "$scripts" == *"build"* ]] && build_cmd="npm run build 2>&1; echo \$?"

    # Fallback lint
    if [ -z "$lint_cmd" ]; then
      if [ -f "$PROJECT_ROOT/.eslintrc.js" ] || [ -f "$PROJECT_ROOT/.eslintrc.json" ] || [ -f "$PROJECT_ROOT/eslint.config.js" ] || [ -f "$PROJECT_ROOT/eslint.config.mjs" ]; then
        lint_cmd="npx eslint . --format compact 2>&1 | wc -l"
      fi
    fi

  elif [ -f "$PROJECT_ROOT/pyproject.toml" ] || [ -f "$PROJECT_ROOT/setup.py" ]; then
    # Python project
    if [ -f "$PROJECT_ROOT/pyproject.toml" ] && grep -q "pytest" "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
      test_cmd="python3 -m pytest 2>&1"
    elif [ -d "$PROJECT_ROOT/tests" ]; then
      test_cmd="python3 -m pytest 2>&1"
    fi

    command -v ruff &>/dev/null && lint_cmd="ruff check . 2>&1 | wc -l"
    command -v mypy &>/dev/null && type_cmd="mypy . 2>&1 | grep -c 'error' || true"
    build_cmd="python3 -m py_compile \$(find . -name '*.py' -not -path '*/venv/*' -not -path '*/.venv/*' | head -20) 2>&1; echo \$?"

  elif [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
    # Rust project
    test_cmd="cargo test 2>&1"
    lint_cmd="cargo clippy 2>&1 | grep -c 'warning' || true"
    type_cmd="cargo check 2>&1 | grep -c 'error' || true"
    build_cmd="cargo build 2>&1; echo \$?"

  elif [ -f "$PROJECT_ROOT/go.mod" ]; then
    # Go project
    test_cmd="go test ./... 2>&1"
    lint_cmd="go vet ./... 2>&1 | wc -l"
    build_cmd="go build ./... 2>&1; echo \$?"
  fi

  # Output as JSON
  python3 -c "
import json
d = {}
if '$test_cmd': d['test'] = '$test_cmd'
if '$lint_cmd': d['lint'] = '$lint_cmd'
if '$type_cmd': d['type'] = '$type_cmd'
if '$build_cmd': d['build'] = '$build_cmd'
d['guard'] = d.get('test', '')
print(json.dumps(d))
"
}

# --- Read config or use defaults ---
never_touch='["*.lock", "node_modules/**", "vendor/**", ".env*", "*.min.js", "*.min.css", "dist/**", "build/**"]'
if [ -f "$AR_DIR/config.json" ]; then
  config_never=$(python3 -c "import json; print(json.dumps(json.load(open('$AR_DIR/config.json')).get('never_touch', [])))" 2>/dev/null)
  [ -n "$config_never" ] && [ "$config_never" != "[]" ] && never_touch="$config_never"
fi

# --- Create branch ---
git checkout -b "$BRANCH" 2>/dev/null || {
  echo "WARNING: Branch $BRANCH already exists or could not be created." >&2
  BRANCH=$(git branch --show-current)
}

# --- Detect frozen commands ---
frozen_commands=$(detect_commands)

# --- Run baseline metrics ---
echo "Running baseline metrics..." >&2
baseline_results="{}"
for metric in test lint type build; do
  cmd=$(echo "$frozen_commands" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$metric',''))" 2>/dev/null)
  if [ -n "$cmd" ]; then
    result=$(eval "$cmd" 2>/dev/null | tail -1 || echo "error")
    baseline_results=$(echo "$baseline_results" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['$metric'] = '''$result'''.strip()
print(json.dumps(d))
" 2>/dev/null)
  fi
done

# --- Create .autoresearch directory ---
mkdir -p "$AR_DIR/metrics"

# --- Write state.json ---
cat > "$AR_DIR/state.json" << STATEJSON
{
  "version": 3,
  "project": "$(basename "$PROJECT_ROOT")",
  "branch": "$BRANCH",
  "mode": "$MODE",
  "start": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "experiment": 0,
  "state": "BOOTSTRAP",
  "kept": 0,
  "discarded": 0,
  "consecutive_discards": 0,
  "strategy": "default",
  "max_experiments": $MAX_EXPERIMENTS,
  "baseline": $baseline_results,
  "best": $baseline_results,
  "frozen_commands": $frozen_commands,
  "never_touch": $never_touch,
  "failed_targets": {},
  "discoveries": []
}
STATEJSON

# --- Write results.tsv ---
echo -e "exp\tcommit\ttests\tlint\ttypes\tbuild\tguard\tstatus\tfile\tdescription\trationale" > "$AR_DIR/results.tsv"
echo -e "0\t$(git rev-parse --short HEAD 2>/dev/null || echo '-')\t-\t-\t-\t-\t-\tbaseline\t-\tinitial state\t-" >> "$AR_DIR/results.tsv"

# --- Write CHECKPOINT.md ---
cat > "$AR_DIR/CHECKPOINT.md" << 'CHECKPOINT'
# Ratchet Checkpoint

## Context & Orientation
<!-- Project description, tech stack, current state — enough for zero-context resume -->

## Progress
- [x] Bootstrap completed

## Decision Log
| # | Decision | Reason | Alternative |
|---|----------|--------|-------------|

## Surprises & Discoveries
<!-- Unexpected findings during experiments -->

## Current Strategy
`default` — standard improvement targeting highest-impact files first
CHECKPOINT

# --- Write NOTES.md ---
cat > "$AR_DIR/NOTES.md" << NOTES
# Ratchet Notes

**Project:** $(basename "$PROJECT_ROOT")
**Mode:** $MODE
**Branch:** $BRANCH
**Started:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Baseline Metrics
$baseline_results

## Observations
NOTES

# --- Write baseline metrics ---
echo "$baseline_results" > "$AR_DIR/metrics/baseline.json"
echo "$baseline_results" > "$AR_DIR/metrics/latest.json"

# --- Set active flag ---
echo "$PROJECT_ROOT" > "$AR_ACTIVE_FLAG"
echo "$PROJECT_ROOT" > "$AR_ROOT_CACHE"

# --- Transition to SELECT_TARGET ---
source "$SCRIPT_DIR/_lib.sh"
ar_state_set "state" '"SELECT_TARGET"'
ar_log "info" "bootstrap complete: mode=$MODE branch=$BRANCH"

echo "Ratchet initialized: mode=$MODE, branch=$BRANCH" >&2
echo "State: SELECT_TARGET — ready for first experiment." >&2

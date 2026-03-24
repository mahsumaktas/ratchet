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
  state=$(AR_PATH="$AR_DIR/state.json" python3 -c "import json,os; print(json.load(open(os.environ['AR_PATH'])).get('state',''))" 2>/dev/null)
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
    scripts=$(AR_PKG="$PROJECT_ROOT/package.json" python3 -c "import json,os; s=json.load(open(os.environ['AR_PKG'])).get('scripts',{}); print(' '.join(s.keys()))" 2>/dev/null || echo "")

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
  AR_TEST="$test_cmd" AR_LINT="$lint_cmd" AR_TYPE="$type_cmd" AR_BUILD="$build_cmd" python3 -c "
import json, os
d = {}
for key, env in [('test','AR_TEST'),('lint','AR_LINT'),('type','AR_TYPE'),('build','AR_BUILD')]:
    v = os.environ.get(env, '')
    if v: d[key] = v
d['guard'] = d.get('test', '')
print(json.dumps(d))
"
}

# --- Read config or use defaults ---
never_touch='["*.lock", "node_modules/**", "vendor/**", ".env*", "*.min.js", "*.min.css", "dist/**", "build/**"]'
if [ -f "$AR_DIR/config.json" ]; then
  config_never=$(AR_CFG="$AR_DIR/config.json" python3 -c "import json,os; print(json.dumps(json.load(open(os.environ['AR_CFG'])).get('never_touch', [])))" 2>/dev/null)
  [ -n "$config_never" ] && [ "$config_never" != "[]" ] && never_touch="$config_never"
fi

# --- Create branch ---
git checkout -b "$BRANCH" 2>/dev/null || {
  echo "WARNING: Branch $BRANCH already exists or could not be created." >&2
  BRANCH=$(git branch --show-current)
}

# --- Detect frozen commands ---
frozen_commands=$(detect_commands)

# Environment probing
PROBE_RESULT=$("$SCRIPT_DIR/ar-probe.sh" "$PROJECT_ROOT" 2>/dev/null || echo '{}')

# --- Run baseline metrics ---
echo "Running baseline metrics..." >&2
baseline_results="{}"
for metric in test lint type build; do
  cmd=$(AR_METRIC="$metric" python3 -c "import json,sys,os; print(json.load(sys.stdin).get(os.environ['AR_METRIC'],''))" 2>/dev/null <<< "$frozen_commands")
  if [ -n "$cmd" ]; then
    result=$(eval "$cmd" 2>/dev/null | tail -1 || echo "error")
    baseline_results=$(AR_METRIC="$metric" AR_RESULT="$result" python3 -c "
import json, sys, os
d = json.load(sys.stdin)
d[os.environ['AR_METRIC']] = os.environ['AR_RESULT'].strip()
print(json.dumps(d))
" 2>/dev/null <<< "$baseline_results")
  fi
done

# --- Create .autoresearch directory ---
mkdir -p "$AR_DIR/metrics"

# Prune old lessons and load existing ones
"$SCRIPT_DIR/ar-lessons.sh" prune 2>/dev/null || true
EXISTING_LESSONS=$("$SCRIPT_DIR/ar-lessons.sh" read 2>/dev/null || echo "")

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
  "discoveries": [],
  "environment": $PROBE_RESULT
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

if [ -n "$EXISTING_LESSONS" ]; then
  cat >> "$AR_DIR/CHECKPOINT.md" << LESSONS

## Lessons from Previous Runs
$EXISTING_LESSONS
LESSONS
fi

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
ar_log "info" "bootstrap" "complete" "mode=$MODE" "branch=$BRANCH"

echo "Ratchet initialized: mode=$MODE, branch=$BRANCH" >&2
echo "State: SELECT_TARGET — ready for first experiment." >&2

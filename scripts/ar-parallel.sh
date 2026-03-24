#!/usr/bin/env bash
# ar-parallel.sh — Run parallel experiments in isolated git worktrees
# Usage: ar-parallel.sh run [count] [strategies...]
# Example: ar-parallel.sh run 3 default low-hanging-fruit deep-refactor
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

cmd="${1:-help}"
shift || true

case "$cmd" in
  run)
    count="${1:-3}"
    shift || true

    root="$(ar_project_root 2>/dev/null)" || root="$PWD"
    base_branch=$(git -C "$root" branch --show-current 2>/dev/null || echo "main")
    worktree_base="/tmp/ar-worktrees-$$"
    results_file="$root/.autoresearch/parallel-results.json"

    # Default strategies if none provided
    strategies=("${@:-default low-hanging-fruit deep-refactor security dead-code}")
    if [ $# -eq 0 ]; then
      strategies=(default low-hanging-fruit deep-refactor security dead-code)
    fi

    # Limit to requested count
    strategies=("${strategies[@]:0:$count}")

    echo "[PARALLEL] Starting ${#strategies[@]} parallel experiments from branch $base_branch" >&2
    mkdir -p "$worktree_base" "$(dirname "$results_file")"

    # Create worktrees and run experiments
    pids=()
    wt_dirs=()
    for i in "${!strategies[@]}"; do
      strategy="${strategies[$i]}"
      wt_dir="$worktree_base/exp-$i-$strategy"
      branch_name="ar-parallel-$$-$i"

      # Create worktree
      git -C "$root" worktree add -b "$branch_name" "$wt_dir" "$base_branch" 2>/dev/null || {
        echo "[PARALLEL] Failed to create worktree for $strategy, skipping" >&2
        continue
      }

      wt_dirs+=("$wt_dir")

      # Run experiment in background
      (
        cd "$wt_dir"

        # Run frozen commands to get baseline
        state_file="$root/.autoresearch/state.json"
        if [ -f "$state_file" ]; then
          guard_cmd=$(AR_FIELD="frozen_commands.guard" AR_PATH="$state_file" python3 -c "
import json, os
with open(os.environ['AR_PATH']) as f:
    d = json.load(f)
keys = os.environ['AR_FIELD'].split('.')
val = d
for k in keys:
    val = val.get(k, '') if isinstance(val, dict) else ''
print(val if val != '' else '')
" 2>/dev/null || echo "")

          if [ -n "$guard_cmd" ]; then
            guard_result=$(cd "$wt_dir" && eval "$guard_cmd" 2>/dev/null | tail -1 || echo "error")
          else
            guard_result="skip"
          fi
        fi

        # Write result
        AR_STRATEGY="$strategy" AR_INDEX="$i" AR_GUARD="$guard_result" AR_DIR="$wt_dir" python3 -c "
import json, os
result = {
    'strategy': os.environ['AR_STRATEGY'],
    'index': int(os.environ['AR_INDEX']),
    'worktree': os.environ['AR_DIR'],
    'guard_result': os.environ['AR_GUARD'],
    'status': 'ready'
}
print(json.dumps(result))
" > "$wt_dir/.ar-parallel-result.json" 2>/dev/null

      ) &
      pids+=($!)
      echo "[PARALLEL] Started experiment $i: strategy=$strategy pid=$!" >&2
    done

    # Wait for all experiments
    failed=0
    for pid in "${pids[@]}"; do
      wait "$pid" 2>/dev/null || ((failed++))
    done

    # Collect results
    AR_BASE="$worktree_base" AR_COUNT="${#wt_dirs[@]}" python3 -c "
import json, os, glob

base = os.environ['AR_BASE']
results = []
for f in sorted(glob.glob(f'{base}/exp-*/.ar-parallel-result.json')):
    try:
        with open(f) as fh:
            results.append(json.load(fh))
    except: pass

print(json.dumps({'experiments': results, 'total': len(results), 'failed': int(os.environ.get('AR_FAILED', '0'))}, indent=2))
" 2>/dev/null

    # Cleanup worktrees
    for wt_dir in "${wt_dirs[@]}"; do
      branch_name=$(git -C "$wt_dir" branch --show-current 2>/dev/null || echo "")
      git -C "$root" worktree remove --force "$wt_dir" 2>/dev/null || true
      [ -n "$branch_name" ] && git -C "$root" branch -D "$branch_name" 2>/dev/null || true
    done
    rm -rf "$worktree_base" 2>/dev/null || true

    echo "[PARALLEL] Complete: ${#wt_dirs[@]} experiments, $failed failed" >&2
    ;;

  help|--help|-h)
    cat >&2 << 'HELP'
ar-parallel.sh — Run parallel experiments in isolated git worktrees

Usage:
  ar-parallel.sh run [count] [strategies...]
  ar-parallel.sh help

Examples:
  ar-parallel.sh run 3                    # 3 experiments with default strategies
  ar-parallel.sh run 5 default security   # 5 experiments, specific strategies

Strategies: default, low-hanging-fruit, deep-refactor, security, dead-code, discovery
HELP
    ;;

  *)
    echo "Unknown command: $cmd. Use 'ar-parallel.sh help'" >&2
    exit 1
    ;;
esac

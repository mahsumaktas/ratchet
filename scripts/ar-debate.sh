#!/usr/bin/env bash
# ar-debate.sh — Multi-agent debate: 5 expert personas evaluate changes
# Usage: ar-debate.sh evaluate <file> <diff_summary>
# Returns: JSON verdict with consensus score
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

cmd="${1:-help}"
shift || true

case "$cmd" in
  evaluate)
    file="${1:-}"
    diff_summary="${2:-unknown change}"

    root="$(ar_project_root 2>/dev/null)" || root="$PWD"

    AR_FILE="$file" AR_DIFF="$diff_summary" AR_ROOT="$root" python3 -c "
import json, os

file = os.environ.get('AR_FILE', '')
diff = os.environ.get('AR_DIFF', '')
root = os.environ.get('AR_ROOT', '.')

# 5 Expert Personas — each evaluates from their perspective
personas = [
    {
        'role': 'Competitor',
        'perspective': 'Would a senior dev at a top company approve this change?',
        'criteria': ['code clarity', 'naming conventions', 'single responsibility'],
        'weight': 1.0
    },
    {
        'role': 'Analyst',
        'perspective': 'Does this change have measurable positive impact?',
        'criteria': ['metric improvement', 'performance impact', 'test coverage'],
        'weight': 1.2
    },
    {
        'role': 'Coach',
        'perspective': 'Does this teach good patterns to the codebase?',
        'criteria': ['maintainability', 'readability', 'documentation'],
        'weight': 0.8
    },
    {
        'role': 'Architect',
        'perspective': 'Does this fit the overall system design?',
        'criteria': ['coupling', 'cohesion', 'abstraction level'],
        'weight': 1.0
    },
    {
        'role': 'Curator',
        'perspective': 'Is this change worth the complexity it adds?',
        'criteria': ['YAGNI', 'simplicity', 'reversibility'],
        'weight': 0.9
    }
]

# Build evaluation prompt for SKILL.md to use with Agent tool
debate = {
    'file': file,
    'diff_summary': diff,
    'personas': personas,
    'instructions': 'Evaluate this change from each persona perspective. Score 1-10 per persona. Consensus = weighted average >= 7 means APPROVE.',
    'output_format': {
        'scores': {p['role']: {'score': 0, 'reasoning': ''} for p in personas},
        'consensus_score': 0.0,
        'verdict': 'APPROVE or REJECT',
        'key_concern': ''
    }
}

print(json.dumps(debate, indent=2))
" 2>/dev/null
    ;;

  roles)
    echo "Available debate roles:"
    echo "  Competitor — Code quality from senior dev perspective"
    echo "  Analyst    — Measurable impact analysis"
    echo "  Coach      — Maintainability and teaching value"
    echo "  Architect  — System design fit"
    echo "  Curator    — Complexity vs value tradeoff"
    ;;

  help|--help|-h)
    cat >&2 << 'HELP'
ar-debate.sh — Multi-agent debate for change evaluation

Usage:
  ar-debate.sh evaluate <file> <diff_summary>
  ar-debate.sh roles
  ar-debate.sh help

The debate system provides a structured evaluation framework.
Claude Code uses this with Agent tool to spawn read-only
subagents for each persona.

Consensus threshold: weighted average >= 7.0 = APPROVE
HELP
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac

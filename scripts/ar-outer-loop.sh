#!/usr/bin/env bash
# ar-outer-loop.sh — Meta-optimization: optimize ratchet's own parameters
# Analyzes cross-session performance to tune thresholds, strategy ordering, timing
# Usage: ar-outer-loop.sh analyze|optimize|report
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

root="$(ar_project_root 2>/dev/null)" || root="$PWD"
INSIGHTS_FILE="$root/.autoresearch/logs/insights.jsonl"
EXPERIMENTS_FILE="$root/.autoresearch/logs/experiments.jsonl"
CONFIG_FILE="$root/.autoresearch/config.json"

cmd="${1:-report}"
shift || true

case "$cmd" in
  analyze)
    # Deep analysis of experiment history — find meta-patterns
    [ -f "$EXPERIMENTS_FILE" ] || { echo "No experiments data"; exit 0; }

    AR_EXPERIMENTS="$EXPERIMENTS_FILE" AR_INSIGHTS="$INSIGHTS_FILE" python3 -c "
import json, os
from collections import defaultdict
from datetime import datetime, timezone

def load_jsonl(path):
    entries = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try: entries.append(json.loads(line))
                    except: continue
    except FileNotFoundError: pass
    return entries

experiments = load_jsonl(os.environ['AR_EXPERIMENTS'])
if not experiments:
    print(json.dumps({'status': 'no data'}))
    exit(0)

# Meta-analysis
analysis = {
    'total_experiments': len(experiments),
    'total_kept': sum(1 for e in experiments if e.get('decision') == 'KEEP'),
    'overall_success_rate': 0,
    'strategy_performance': {},
    'time_patterns': {},
    'file_type_performance': {},
    'optimal_parameters': {}
}

analysis['overall_success_rate'] = round(
    analysis['total_kept'] / len(experiments) if experiments else 0, 3
)

# Strategy performance ranking
strat_groups = defaultdict(list)
for e in experiments:
    strat_groups[e.get('strategy', 'unknown')].append(e)

for strat, exps in strat_groups.items():
    kept = sum(1 for e in exps if e.get('decision') == 'KEEP')
    analysis['strategy_performance'][strat] = {
        'total': len(exps),
        'kept': kept,
        'success_rate': round(kept / len(exps), 3) if exps else 0,
        'avg_duration_sec': round(
            sum(e.get('duration_sec', 0) for e in exps) / len(exps), 1
        ) if exps else 0
    }

# File type performance
ext_groups = defaultdict(list)
for e in experiments:
    target = e.get('target_file', '')
    ext = '.' + target.rsplit('.', 1)[-1] if '.' in target else 'unknown'
    ext_groups[ext].append(e)

for ext, exps in ext_groups.items():
    kept = sum(1 for e in exps if e.get('decision') == 'KEEP')
    analysis['file_type_performance'][ext] = {
        'total': len(exps),
        'kept': kept,
        'success_rate': round(kept / len(exps), 3) if exps else 0
    }

# Optimal parameters suggestions
sorted_strats = sorted(
    analysis['strategy_performance'].items(),
    key=lambda x: x[1]['success_rate'],
    reverse=True
)
analysis['optimal_parameters'] = {
    'recommended_strategy_order': [s[0] for s in sorted_strats if s[1]['success_rate'] > 0],
    'avoid_strategies': [s[0] for s in sorted_strats if s[1]['total'] >= 3 and s[1]['success_rate'] == 0],
    'best_file_types': sorted(
        [(ext, d['success_rate']) for ext, d in analysis['file_type_performance'].items()],
        key=lambda x: x[1], reverse=True
    )[:5]
}

print(json.dumps(analysis, indent=2))
" 2>/dev/null
    ;;

  optimize)
    # Apply meta-optimization to config
    [ -f "$EXPERIMENTS_FILE" ] || { echo "No experiments data to optimize from"; exit 0; }

    analysis=$("$0" analyze 2>/dev/null) || { echo "Analysis failed"; exit 1; }

    AR_ANALYSIS="$analysis" AR_CONFIG="$CONFIG_FILE" python3 -c "
import json, os

analysis = json.loads(os.environ['AR_ANALYSIS'])
config_path = os.environ['AR_CONFIG']

try:
    with open(config_path) as f:
        config = json.load(f)
except:
    config = {}

actions = []

# Apply recommended strategy order
recommended = analysis.get('optimal_parameters', {}).get('recommended_strategy_order', [])
if recommended and len(recommended) >= 2:
    old = config.get('strategy_rotation', [])
    config['strategy_rotation'] = recommended
    actions.append(f'strategy_rotation: {old} -> {recommended}')

# Remove avoid strategies
avoid = analysis.get('optimal_parameters', {}).get('avoid_strategies', [])
if avoid:
    current = config.get('strategy_rotation', [])
    config['strategy_rotation'] = [s for s in current if s not in avoid]
    actions.append(f'removed strategies: {avoid}')

# Save config backup + update
if actions:
    import shutil, time
    backup = config_path + f'.bak.outer-{int(time.time())}'
    try: shutil.copy2(config_path, backup)
    except: pass

    # Never touch protected fields
    protected = {'guard_command', 'frozen_commands', 'mode', 'max_experiments'}
    try:
        with open(config_path) as f:
            original = json.load(f)
        for field in protected:
            if field in original:
                config[field] = original[field]
    except: pass

    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)

print(json.dumps({
    'actions': actions,
    'optimized': len(actions) > 0,
    'analysis_summary': {
        'total_experiments': analysis['total_experiments'],
        'success_rate': analysis['overall_success_rate'],
    }
}, indent=2))
" 2>/dev/null
    ;;

  report)
    analysis=$("$0" analyze 2>/dev/null) || { echo "No data"; exit 0; }

    echo "$analysis" | python3 -c "
import json, sys

d = json.load(sys.stdin)
total = d.get('total_experiments', 0)
kept = d.get('total_kept', 0)
rate = d.get('overall_success_rate', 0)

print(f'=== Ratchet Outer Loop Report ===')
print(f'Total: {total} experiments, {kept} kept ({rate*100:.1f}% success)')
print()
print('Strategy Performance:')
for strat, data in sorted(d.get('strategy_performance', {}).items(), key=lambda x: x[1]['success_rate'], reverse=True):
    print(f'  {strat}: {data[\"kept\"]}/{data[\"total\"]} ({data[\"success_rate\"]*100:.0f}%) avg {data[\"avg_duration_sec\"]}s')
print()
print('Recommendations:')
recs = d.get('optimal_parameters', {})
order = recs.get('recommended_strategy_order', [])
avoid = recs.get('avoid_strategies', [])
if order: print(f'  Strategy order: {\", \".join(order)}')
if avoid: print(f'  Avoid: {\", \".join(avoid)}')
" 2>/dev/null
    ;;

  help|--help|-h)
    cat >&2 << 'HELP'
ar-outer-loop.sh — Meta-optimization for Ratchet

Usage:
  ar-outer-loop.sh analyze     Analyze experiment history, output JSON
  ar-outer-loop.sh optimize    Apply meta-optimizations to config
  ar-outer-loop.sh report      Human-readable performance report
  ar-outer-loop.sh help        Show this help

The outer loop analyzes patterns across ALL experiments to:
- Rank strategies by actual success rate
- Identify file types with highest improvement potential
- Auto-tune strategy ordering in config
- Remove consistently failing strategies
HELP
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac

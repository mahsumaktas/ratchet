#!/usr/bin/env python3
"""ar-self-review-engine.py — Autonomous self-review for Ratchet.
Analyzes experiments.jsonl, detects patterns, auto-adjusts config."""

import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone

# --- Constants ---
DEFAULT_STRATEGIES = ["default", "low-hanging-fruit", "deep-refactor",
                      "security", "dead-code", "discovery"]
PROTECTED_FIELDS = {"guard_command", "frozen_commands", "mode", "max_experiments"}
MAX_EXPERIMENTS_TO_ANALYZE = 500

# --- Helpers ---
def load_jsonl(path):
    """Load JSONL file, return list of dicts."""
    entries = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except FileNotFoundError:
        pass
    return entries

def load_config(path):
    """Load config.json, return dict with defaults."""
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_config(path, config):
    """Atomically save config.json."""
    tmp = path + '.tmp.' + str(os.getpid())
    with open(tmp, 'w') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    os.rename(tmp, path)

def group_by_key(experiments, key):
    """Group experiments by a key field."""
    groups = defaultdict(list)
    for exp in experiments:
        groups[exp.get(key, 'unknown')].append(exp)
    return groups.items()

def count_trailing_discards(experiments):
    """Count consecutive DISCARDs from the end."""
    count = 0
    for exp in reversed(experiments):
        if exp.get('decision') != 'KEEP':
            count += 1
        else:
            break
    return count

# --- Analysis ---
def analyze_experiments(experiments):
    """Detect patterns in experiment history."""
    experiments = experiments[-MAX_EXPERIMENTS_TO_ANALYZE:]
    findings = []

    # 1. Ineffective strategy (< 10% success, min 5 experiments)
    for strategy, exps in group_by_key(experiments, 'strategy'):
        exps = list(exps)
        kept = sum(1 for e in exps if e.get('decision') == 'KEEP')
        total = len(exps)
        rate = kept / total if total else 0
        if total >= 5 and rate < 0.10:
            findings.append({
                'type': 'strategy_ineffective',
                'strategy': strategy,
                'success_rate': round(rate, 2),
                'total': total, 'kept': kept
            })

    # 2. Resistant file (3+ consecutive failures)
    for file, exps in group_by_key(experiments, 'target_file'):
        exps = list(exps)
        trailing = count_trailing_discards(exps)
        if trailing >= 3:
            findings.append({
                'type': 'file_resistant',
                'file': file,
                'consecutive_failures': trailing
            })

    # 3. Local minimum (last 10 all discarded)
    recent = experiments[-10:]
    if len(recent) >= 10 and all(e.get('decision') != 'KEEP' for e in recent):
        findings.append({'type': 'local_minimum', 'last_n': 10})

    # 4. Effective strategy (> 70% success, min 5 experiments)
    for strategy, exps in group_by_key(experiments, 'strategy'):
        exps = list(exps)
        kept = sum(1 for e in exps if e.get('decision') == 'KEEP')
        total = len(exps)
        rate = kept / total if total else 0
        if total >= 5 and rate > 0.70:
            findings.append({
                'type': 'strategy_effective',
                'strategy': strategy,
                'success_rate': round(rate, 2)
            })

    return findings

# --- Actions ---
def apply_actions(config, findings):
    """Apply findings to config. Returns list of actions taken."""
    actions = []
    strategies = config.get('strategy_rotation', list(DEFAULT_STRATEGIES))

    for f in findings:
        if f['type'] == 'strategy_ineffective':
            s = f['strategy']
            if s in strategies and len(strategies) > 1:
                strategies.remove(s)
                actions.append({
                    'type': 'remove_strategy', 'strategy': s,
                    'reason': f"{f['kept']}/{f['total']} kept ({f['success_rate']*100:.0f}%)"
                })

        elif f['type'] == 'file_resistant':
            nt = config.get('never_touch', [])
            if f['file'] not in nt:
                nt.append(f['file'])
                config['never_touch'] = nt
                actions.append({
                    'type': 'add_never_touch', 'pattern': f['file'],
                    'reason': f"{f['consecutive_failures']} consecutive failures"
                })

        elif f['type'] == 'local_minimum':
            strategies = list(DEFAULT_STRATEGIES)
            if 'discovery' not in strategies:
                strategies.append('discovery')
            actions.append({
                'type': 'reset_strategies',
                'reason': 'local minimum detected — last 10 experiments all discarded'
            })

        elif f['type'] == 'strategy_effective':
            s = f['strategy']
            if s in strategies:
                strategies.remove(s)
                strategies.insert(0, s)
                actions.append({
                    'type': 'prioritize_strategy', 'strategy': s,
                    'reason': f"{f['success_rate']*100:.0f}% success rate"
                })

    config['strategy_rotation'] = strategies
    return actions

# --- Main ---
def main():
    trigger = os.environ.get('AR_TRIGGER', 'manual')
    experiments_path = os.environ.get('AR_EXPERIMENTS', '')
    config_path = os.environ.get('AR_CONFIG', '')
    insights_path = os.environ.get('AR_INSIGHTS', '')
    checkpoint_path = os.environ.get('AR_CHECKPOINT', '')

    if not experiments_path:
        return

    experiments = load_jsonl(experiments_path)
    if not experiments:
        return

    config = load_config(config_path)
    findings = analyze_experiments(experiments)

    if not findings:
        return

    actions = apply_actions(config, findings)

    # Save updated config (only if actions were taken)
    if actions and config_path:
        # Ensure protected fields are never modified — load original once
        original = load_config(config_path)
        for field in PROTECTED_FIELDS:
            if field in original:
                config[field] = original[field]
        save_config(config_path, config)

    # Write insight
    insight = {
        'ts': datetime.now(timezone.utc).isoformat(),
        'trigger': trigger,
        'total_experiments': len(experiments),
        'findings': findings,
        'actions_taken': actions,
    }

    if insights_path:
        os.makedirs(os.path.dirname(insights_path), exist_ok=True)
        with open(insights_path, 'a') as f:
            f.write(json.dumps(insight, ensure_ascii=False) + '\n')

    # Append to CHECKPOINT.md
    if checkpoint_path and os.path.exists(checkpoint_path) and actions:
        summary_parts = [f"- Self-review ({trigger}): "]
        for a in actions:
            summary_parts.append(f"  - {a['type']}: {a.get('strategy', a.get('pattern', ''))} ({a['reason']})")
        with open(checkpoint_path, 'a') as f:
            f.write('\n' + '\n'.join(summary_parts) + '\n')

    # Print summary to stderr for Claude to see
    if actions:
        print(f"[SELF-REVIEW] {len(findings)} findings, {len(actions)} actions taken", file=sys.stderr)
        for a in actions:
            print(f"  {a['type']}: {a.get('strategy', a.get('pattern', '?'))} — {a['reason']}", file=sys.stderr)

if __name__ == '__main__':
    main()

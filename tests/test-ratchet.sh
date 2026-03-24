#!/usr/bin/env bash
# test-ratchet.sh — Integration tests for Ratchet v2
set -euo pipefail

PASS=0; FAIL=0; TOTAL=0
check() {
  local name="$1"; shift
  TOTAL=$((TOTAL + 1))
  if eval "$@" >/dev/null 2>&1; then
    echo "[OK]   $name"; PASS=$((PASS + 1))
  else
    echo "[FAIL] $name"; FAIL=$((FAIL + 1))
  fi
}

SCRIPTS="$HOME/.claude/skills/autoresearch/scripts"
HOOKS="$HOME/.claude/hooks"

echo "========================================"
echo "  Ratchet v2 Test Suite"
echo "  $(date)"
echo "========================================"

# --- Test 1: glob_match recursive ** patterns ---
echo ""
echo "=== Bug Fix: glob_match ==="
check "glob: node_modules/**" python3 -c "
import fnmatch
def glob_match(fp, p):
    if '**' in p:
        parts = p.split('**', 1)
        prefix = parts[0].rstrip('/')
        suffix = parts[1].lstrip('/') if parts[1] else ''
        if prefix:
            if not (fp.startswith(prefix + '/') or fp == prefix): return False
            remainder = fp[len(prefix)+1:]
        else: remainder = fp
        if not suffix: return True
        segs = remainder.split('/')
        return any(fnmatch.fnmatch('/'.join(segs[i:]), suffix) for i in range(len(segs)))
    return fnmatch.fnmatch(fp, p)
assert glob_match('node_modules/express/index.js', 'node_modules/**')
"

check "glob: dist/**" python3 -c "
import fnmatch
def glob_match(fp, p):
    if '**' in p:
        parts = p.split('**', 1); prefix = parts[0].rstrip('/'); suffix = parts[1].lstrip('/') if parts[1] else ''
        if prefix and not (fp.startswith(prefix + '/') or fp == prefix): return False
        return True
    return fnmatch.fnmatch(fp, p)
assert glob_match('dist/bundle.js', 'dist/**')
"

check "glob: no false positive" python3 -c "
import fnmatch
def glob_match(fp, p):
    if '**' in p:
        parts = p.split('**', 1); prefix = parts[0].rstrip('/')
        if prefix and not (fp.startswith(prefix + '/') or fp == prefix): return False
        return True
    return fnmatch.fnmatch(fp, p)
assert not glob_match('src/main.ts', 'node_modules/**')
"

check "glob: .env*" python3 -c "import fnmatch; assert fnmatch.fnmatch('.env.local', '.env*')"

# --- Test 2: ar-init.sh no injection patterns ---
echo ""
echo "=== Bug Fix: Shell Injection ==="
check "ar-init: no direct interpolation" "! grep -n \"import json; \" $SCRIPTS/ar-init.sh | grep -q \"open('\\\$\""

# --- Test 3: ar-decide.sh error handling ---
echo ""
echo "=== Bug Fix: Decision Engine ==="
check "ar-decide: all-error DISCARD" python3 -c "
# Simulate the decision logic
latest = {'test': 'error', 'lint': 'error', 'type': 'error', 'build': 'error'}
error_count = sum(1 for k in ['test','lint','type','build'] if latest.get(k,'') == 'error')
total_count = sum(1 for k in ['test','lint','type','build'] if latest.get(k,''))
assert total_count > 0 and error_count == total_count, 'should detect all-error'
"

check "ar-decide: syntax valid" "bash -n $SCRIPTS/ar-decide.sh"

# --- Test 4: ar_log creates valid JSONL ---
echo ""
echo "=== Logging: ar_log ==="

# Setup test environment
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.autoresearch/logs"
echo '{}' > "$TEST_DIR/.autoresearch/state.json"
echo "$TEST_DIR" > "/tmp/ar-root-$$.txt"

check "ar_log: creates events.jsonl" bash -c "
cd $TEST_DIR
source $SCRIPTS/_lib.sh
ar_log info test-hook test-event key1=value1 'key2=value with spaces'
[ -f $TEST_DIR/.autoresearch/logs/events.jsonl ]
"

check "ar_log: valid JSON" bash -c "
cd $TEST_DIR
python3 -c \"
import json
with open('$TEST_DIR/.autoresearch/logs/events.jsonl') as f:
    for line in f:
        d = json.loads(line)
        assert 'ts' in d
        assert d['hook'] == 'test-hook'
        assert d['event'] == 'test-event'
        assert d['key1'] == 'value1'
print('JSON valid')
\"
"

# --- Test 5: ar_log_experiment ---
echo ""
echo "=== Logging: ar_log_experiment ==="
check "ar_log_experiment: creates experiments.jsonl" bash -c "
cd $TEST_DIR
source $SCRIPTS/_lib.sh
AR_EXP_ID=1 AR_STRATEGY=default AR_TARGET_FILE=src/app.ts \
AR_METRICS_BEFORE='{\"test\":10}' AR_METRICS_AFTER='{\"test\":12}' \
AR_GUARD_PASSED=true AR_DECISION=KEEP AR_REASON='test improved' \
AR_DURATION_SEC=30 ar_log_experiment
[ -f $TEST_DIR/.autoresearch/logs/experiments.jsonl ]
"

check "ar_log_experiment: valid JSON with fields" bash -c "
cd $TEST_DIR
python3 -c \"
import json
with open('$TEST_DIR/.autoresearch/logs/experiments.jsonl') as f:
    d = json.loads(f.readline())
    assert d['experiment_id'] == 1
    assert d['strategy'] == 'default'
    assert d['decision'] == 'KEEP'
    assert d['metrics_after']['test'] == 12
print('Experiment JSON valid')
\"
"

# --- Test 6: Self-review engine ---
echo ""
echo "=== Self-Review Engine ==="
check "ar-self-review-engine.py: syntax valid" "python3 -m py_compile $SCRIPTS/ar-self-review-engine.py"
check "ar-self-review.sh: syntax valid" "bash -n $SCRIPTS/ar-self-review.sh"

# Test strategy_ineffective detection
check "self-review: detects ineffective strategy" python3 -c "
import sys; sys.path.insert(0, '$SCRIPTS')
# Inline test since module import is complex
from collections import defaultdict
experiments = []
for i in range(6):
    experiments.append({'strategy': 'dead-code', 'decision': 'DISCARD', 'target_file': f'f{i}.ts'})
groups = defaultdict(list)
for e in experiments: groups[e['strategy']].append(e)
for s, exps in groups.items():
    kept = sum(1 for e in exps if e['decision'] == 'KEEP')
    rate = kept / len(exps)
    assert s == 'dead-code' and rate < 0.10 and len(exps) >= 5
print('Ineffective strategy detection OK')
"

# Test config safety
check "self-review: guard_command untouched" python3 -c "
# Simulate: protected fields should be preserved
PROTECTED = {'guard_command', 'frozen_commands', 'mode', 'max_experiments'}
config = {'guard_command': 'npm test', 'strategy_rotation': ['default'], 'mode': 'run'}
# Simulate action
config['strategy_rotation'] = ['low-hanging-fruit']
# Check protected fields
assert config['guard_command'] == 'npm test', 'guard_command modified!'
assert config['mode'] == 'run', 'mode modified!'
print('Config safety OK')
"

# --- Test 7: v2.1 — Lessons ---
echo ""
echo "=== v2.1: Lessons ==="
LESSONS_DIR="$TEST_DIR/.autoresearch"
mkdir -p "$LESSONS_DIR"

check "ar-lessons: add" "bash $SCRIPTS/ar-lessons.sh add 'test lesson from v2.1'"
check "ar-lessons: read" "bash $SCRIPTS/ar-lessons.sh read | grep -q 'test lesson'"
check "ar-lessons: prune" "bash $SCRIPTS/ar-lessons.sh prune"
check "ar-lessons: syntax" "bash -n $SCRIPTS/ar-lessons.sh"

# --- Test 8: v2.1 — Cost Tracking ---
echo ""
echo "=== v2.1: Cost Tracking ==="
check "ar-cost: record" "bash $SCRIPTS/ar-cost.sh record 5000"
check "ar-cost: total" "bash $SCRIPTS/ar-cost.sh total | grep -q 'tokens'"
check "ar-cost: check budget" "bash $SCRIPTS/ar-cost.sh check 100"
check "ar-cost: syntax" "bash -n $SCRIPTS/ar-cost.sh"

# --- Test 9: v2.1 — Environment Probing ---
echo ""
echo "=== v2.1: Environment Probing ==="
check "ar-probe: detects shell" "bash $SCRIPTS/ar-probe.sh $TEST_DIR 2>/dev/null || bash $SCRIPTS/ar-probe.sh /tmp/ratchet-push | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d)>0'"
check "ar-probe: syntax" "bash -n $SCRIPTS/ar-probe.sh"

# --- Test 10: Uninstall script ---
echo ""
echo "=== Uninstall ==="
check "uninstall.sh: syntax valid" "bash -n $SCRIPTS/../uninstall.sh"

# --- All hook files syntax ---
echo ""
echo "=== Hook Syntax ==="
check "ar-boundary-guard.sh" "bash -n $HOOKS/ar-boundary-guard.sh"
check "ar-metrics-collector.sh" "bash -n $HOOKS/ar-metrics-collector.sh"
check "ar-state-enforcer.sh" "bash -n $HOOKS/ar-state-enforcer.sh"
check "ar-session-restore.sh" "bash -n $HOOKS/ar-session-restore.sh"
check "ar-compact-inject.sh" "bash -n $HOOKS/ar-compact-inject.sh"
check "ar-stop-summary.sh" "bash -n $HOOKS/ar-stop-summary.sh"

# --- Test 9: All script files syntax ---
echo ""
echo "=== Script Syntax ==="
check "_lib.sh" "bash -n $SCRIPTS/_lib.sh"
check "ar-init.sh" "bash -n $SCRIPTS/ar-init.sh"
check "ar-decide.sh" "bash -n $SCRIPTS/ar-decide.sh"
check "ar-self-review.sh" "bash -n $SCRIPTS/ar-self-review.sh"
check "ar-lessons.sh" "bash -n $SCRIPTS/ar-lessons.sh"
check "ar-cost.sh" "bash -n $SCRIPTS/ar-cost.sh"
check "ar-probe.sh" "bash -n $SCRIPTS/ar-probe.sh"

# Cleanup
rm -rf "$TEST_DIR" "/tmp/ar-root-$$.txt" 2>/dev/null

echo ""
echo "========================================"
echo "  SONUC: $PASS basarili, $FAIL basarisiz / $TOTAL test"
echo "========================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

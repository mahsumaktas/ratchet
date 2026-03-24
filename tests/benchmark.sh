#!/usr/bin/env bash
# benchmark.sh — Performance benchmarks and stress tests for Ratchet
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR" "/tmp/ar-root-$$.txt" "/tmp/ar-active-$$.txt" "/tmp/ar-root-'"${PPID}"'.txt" "/tmp/ar-active-'"${PPID}"'.txt"' EXIT

# Setup test environment
mkdir -p "$TEST_DIR/.autoresearch/logs" "$TEST_DIR/.autoresearch/metrics"
echo '{}' > "$TEST_DIR/.autoresearch/state.json"
# Create root/active cache for both $$ (for subprocesses where PPID=$$)
# and $PPID (for sourced _lib.sh functions where PPID is our parent)
echo "$TEST_DIR" > "/tmp/ar-root-$$.txt"
echo "$TEST_DIR" > "/tmp/ar-active-$$.txt"
echo "$TEST_DIR" > "/tmp/ar-root-${PPID}.txt"
echo "$TEST_DIR" > "/tmp/ar-active-${PPID}.txt"
cd "$TEST_DIR"

PASS=0; FAIL=0
bench() {
  local name="$1"; shift
  local start=$(date +%s%N)
  if "$@" >/dev/null 2>&1; then
    local end=$(date +%s%N)
    local ms=$(( (end - start) / 1000000 ))
    echo "[BENCH] $name: ${ms}ms"
    PASS=$((PASS + 1))
  else
    echo "[FAIL]  $name"
    FAIL=$((FAIL + 1))
  fi
}

stress() {
  local name="$1" count="$2"; shift 2
  local start=$(date +%s%N)
  local ok=0
  for i in $(seq 1 "$count"); do
    if "$@" >/dev/null 2>&1; then ok=$((ok + 1)); fi
  done
  local end=$(date +%s%N)
  local ms=$(( (end - start) / 1000000 ))
  local avg=$((ms / count))
  echo "[STRESS] $name: ${count}x in ${ms}ms (avg ${avg}ms/call, ${ok}/${count} success)"
  if [ "$ok" -eq "$count" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
}

echo "========================================"
echo "  Ratchet Benchmark Suite"
echo "  $(date)"
echo "========================================"

echo ""
echo "=== Component Benchmarks ==="
source "$SCRIPTS/_lib.sh"

bench "ar_project_root" ar_project_root
bench "ar_state_path" ar_state_path
bench "ar_state_get (field)" ar_state_get "state"
bench "ar_log (single)" ar_log "info" "bench" "test" "key=value"
bench "ar-lessons add" bash "$SCRIPTS/ar-lessons.sh" add "benchmark lesson"
bench "ar-lessons read" bash "$SCRIPTS/ar-lessons.sh" read
bench "ar-cost record" bash "$SCRIPTS/ar-cost.sh" record 1000
bench "ar-cost total" bash "$SCRIPTS/ar-cost.sh" total
bench "ar-probe" bash "$SCRIPTS/ar-probe.sh" "$TEST_DIR"

echo ""
echo "=== Stress Tests ==="

stress "ar_log 100x" 100 ar_log "info" "stress" "iteration" "n=1"
stress "ar-lessons add 50x" 50 bash "$SCRIPTS/ar-lessons.sh" add "stress test lesson"
stress "ar-cost record 50x" 50 bash "$SCRIPTS/ar-cost.sh" record 100
stress "ar_state_get 50x" 50 ar_state_get "state"

echo ""
echo "=== Data Integrity ==="

# Check lessons count (should be capped at 50)
lesson_count=$(wc -l < "$TEST_DIR/.autoresearch/lessons.jsonl" 2>/dev/null || echo 0)
if [ "$lesson_count" -le 50 ]; then
  echo "[OK]    Lessons cap: $lesson_count/50 entries"
  PASS=$((PASS + 1))
else
  echo "[FAIL]  Lessons cap exceeded: $lesson_count entries"
  FAIL=$((FAIL + 1))
fi

# Check cost accumulation
cost_total=$(bash "$SCRIPTS/ar-cost.sh" total 2>/dev/null || echo "error")
echo "[INFO]  Cost total: $cost_total"
if echo "$cost_total" | grep -q "tokens"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
fi

# Check events.jsonl validity
events_count=$(wc -l < "$TEST_DIR/.autoresearch/logs/events.jsonl" 2>/dev/null || echo 0)
valid_json=$(python3 -c "
import json
valid = 0
with open('$TEST_DIR/.autoresearch/logs/events.jsonl') as f:
    for line in f:
        try:
            json.loads(line.strip())
            valid += 1
        except: pass
print(valid)
" 2>/dev/null || echo 0)

if [ "$events_count" -gt 0 ] && [ "$valid_json" -eq "$events_count" ]; then
  echo "[OK]    Events log: $events_count entries, all valid JSON"
  PASS=$((PASS + 1))
else
  echo "[FAIL]  Events log: $events_count entries, $valid_json valid"
  FAIL=$((FAIL + 1))
fi

# Check log rotation trigger
echo ""
echo "=== Log Rotation ==="
# Create a >5MB events file to test rotation
python3 -c "
import json
entry = json.dumps({'ts': '2026-01-01', 'level': 'info', 'hook': 'test', 'event': 'fill'})
with open('$TEST_DIR/.autoresearch/logs/events.jsonl', 'w') as f:
    for i in range(80000):  # ~5.5MB
        f.write(entry + '\n')
" 2>/dev/null

big_size=$(stat -c %s "$TEST_DIR/.autoresearch/logs/events.jsonl" 2>/dev/null || echo 0)
echo "[INFO]  Pre-rotation events.jsonl: ${big_size} bytes"

# Trigger rotation via ar_log (set +e because ar_log's mv -f may fail on non-existent .2/.3 files)
set +e
ar_log "info" "bench" "rotation-trigger" "test=true"
set -e

if [ -f "$TEST_DIR/.autoresearch/logs/events.jsonl.1" ]; then
  echo "[OK]    Log rotation triggered"
  PASS=$((PASS + 1))
else
  echo "[FAIL]  Log rotation not triggered"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "========================================"
echo "  SONUC: $PASS basarili, $FAIL basarisiz"
echo "========================================"
exit $( [ "$FAIL" -eq 0 ] && echo 0 || echo 1 )

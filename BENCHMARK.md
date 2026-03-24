# Ratchet Benchmark Results

**Date:** 2026-03-24
**Platform:** Linux 6.19.9-1-cachyos
**Result:** 17 passed, 0 failed

## Component Benchmarks

| Component | Time |
|-----------|------|
| `ar_project_root` | 0ms |
| `ar_state_path` | 1ms |
| `ar_state_get (field)` | 11ms |
| `ar_log (single)` | 12ms |
| `ar-lessons add` | 14ms |
| `ar-lessons read` | 12ms |
| `ar-cost record` | 13ms |
| `ar-cost total` | 13ms |
| `ar-probe` | 14ms |

## Stress Tests

| Test | Iterations | Total | Avg/call | Success |
|------|-----------|-------|----------|---------|
| `ar_log` | 100x | 1212ms | 12ms | 100/100 |
| `ar-lessons add` | 50x | 710ms | 14ms | 50/50 |
| `ar-cost record` | 50x | 677ms | 13ms | 50/50 |
| `ar_state_get` | 50x | 549ms | 10ms | 50/50 |

## Data Integrity

| Check | Result |
|-------|--------|
| Lessons cap (50 max) | 50/50 entries |
| Cost accumulation | 6K tokens, ~$0.05, 51 experiments |
| Events log validity | 101 entries, all valid JSON |
| Log rotation (>5MB) | Triggered successfully |

## Raw Output

```
========================================
  Ratchet Benchmark Suite
  Sal 24 Mar 2026 23:49:07 +03
========================================

=== Component Benchmarks ===
[BENCH] ar_project_root: 0ms
[BENCH] ar_state_path: 1ms
[BENCH] ar_state_get (field): 11ms
[BENCH] ar_log (single): 12ms
[BENCH] ar-lessons add: 14ms
[BENCH] ar-lessons read: 12ms
[BENCH] ar-cost record: 13ms
[BENCH] ar-cost total: 13ms
[BENCH] ar-probe: 14ms

=== Stress Tests ===
[STRESS] ar_log 100x: 100x in 1212ms (avg 12ms/call, 100/100 success)
[STRESS] ar-lessons add 50x: 50x in 710ms (avg 14ms/call, 50/50 success)
[STRESS] ar-cost record 50x: 50x in 677ms (avg 13ms/call, 50/50 success)
[STRESS] ar_state_get 50x: 50x in 549ms (avg 10ms/call, 50/50 success)

=== Data Integrity ===
[OK]    Lessons cap: 50/50 entries
[INFO]  Cost total: 6K tokens, ~$0.05, 51 experiments
[OK]    Events log: 101 entries, all valid JSON

=== Log Rotation ===
[INFO]  Pre-rotation events.jsonl: 5680000 bytes
[OK]    Log rotation triggered

========================================
  SONUC: 17 basarili, 0 basarisiz
========================================
```

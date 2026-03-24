# Ratchet Summary

**Project:** my-app | **Mode:** fix | **Branch:** autoresearch/20260324-143022
**Started:** 2026-03-24T14:30:22Z

## Metric Changes
| Metric | Start | End | Change |
|--------|-------|-----|--------|
| Tests | 42 | 48 | +6 |
| Lint errors | 23 | 11 | -12 |
| Type errors | 7 | 3 | -4 |
| Build | 0 | 0 | ok |

## Statistics
- Total experiments: 14
- Kept: 8 (57%)
- Discarded: 6
- Strategy changes: 2 (default -> low-hanging-fruit -> security-sweep)
- Guard blocks: 1 (exp-5: test regression prevented)
- Validator FLAGs: 0

## Top 5 Effective Changes
1. `k8l9m0n` — src/api/auth.ts: parameterized SQL query (security fix)
2. `y9z0a1b` — src/services/email.ts: null check + test (P0 bug fix)
3. `q3r4s5t` — src/types/index.ts: type annotation fix (type -1)
4. `m0n1o2p` — src/components/Form.tsx: eslint fixes (lint -2)
5. `c2d3e4f` — src/api/users.ts: dead code removal (lint -1)

## Discoveries
- Found unused 300-line module: `src/utils/deprecated-helpers.ts`
- Database connection pool not properly closed in tests

## Lessons from Failures
- exp-5: Fixing lint in middleware broke auth tests — guard command correctly blocked
- exp-7: `src/legacy/parser.ts` too complex for single-change improvement (blacklisted after 3 attempts)
- exp-10: Code growth without metric improvement correctly rejected by simplicity criterion

## Remaining Work for User
- [ ] Delete `src/utils/deprecated-helpers.ts` (300 lines, unused but may have external dependents)
- [ ] Fix database connection pool leak in test setup
- [ ] Refactor `src/legacy/parser.ts` (requires multi-file change beyond autoresearch scope)

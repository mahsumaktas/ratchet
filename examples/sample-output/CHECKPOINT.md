# Ratchet Checkpoint

## Context & Orientation
Node.js/TypeScript web app with React frontend and Express API. Uses ESLint + TypeScript strict mode. 42 tests at baseline, 23 lint errors, 7 type errors. Goal: drive all errors toward zero.

## Progress
- [x] Bootstrap completed
- [x] Experiments 1-5: default strategy (3 kept, 2 discarded)
- [x] Strategy change: default -> low-hanging-fruit (5 consecutive discards avoided)
- [x] Experiments 6-10: low-hanging-fruit (3 kept, 2 discarded)
- [x] Experiments 11-14: security-sweep triggered by discovery
- [ ] Continue from SELECT_TARGET...

## Decision Log
| # | Decision | Reason | Alternative |
|---|----------|--------|-------------|
| 2 | DISCARD | error handling refactor added complexity without reducing lint | Could try smaller scoped error handling |
| 5 | DISCARD | guard failed: npm test broke when fixing middleware lint | Fix test first, then lint |
| 7 | DISCARD (3rd) | legacy parser too complex, blacklisted | Needs multi-file refactor |
| 10 | DISCARD | code grew by 8 lines, metrics unchanged | Simplicity criterion applied |
| 13 | DISCARD | config simplification had no measurable effect | Low priority, skip |

## Surprises & Discoveries
- **exp-8:** While fixing date.ts, discovered `src/utils/deprecated-helpers.ts` (300 lines, no imports found). Potential dead module.
- **exp-9:** Database connection pool not closed in test teardown. Found while adding email service test. Could cause flaky tests.
- **exp-14:** SQL query in auth.ts was using string interpolation — parameterized to prevent injection.

## Current Strategy
`security-sweep` — triggered by SQL injection discovery in exp-14. Scanning input handlers and auth files.

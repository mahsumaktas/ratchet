# Ratchet

**Autonomous code improvement engine for Claude Code.**

Ratchet makes small, atomic changes to your codebase, measures the impact, and keeps only what improves. Like a ratchet wrench — it only turns forward, never back.

Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch): 126 experiments, 11% improvement, zero human intervention.

---

## Why Ratchet?

Most AI coding tools make large, risky changes. Ratchet takes the opposite approach:

| Traditional AI Coding | Ratchet |
|----------------------|---------|
| Big refactors that might break things | One change at a time |
| "Trust me, it's better" | Frozen metrics prove it |
| Can't undo easily | Git commit or revert, nothing in between |
| Runs once, done | Runs for hours, compounds improvement |
| LLM decides quality | **Scripts decide quality** — deterministic, not probabilistic |

**The key insight:** Claude Code follows markdown instructions, but can forget or skip steps during long sessions. Ratchet adds **enforcement hooks** — bash scripts that mechanically prevent invalid actions. Claude can't commit without passing validation. Can't edit protected files. Can't skip metrics.

## Quick Start

```bash
# Clone and install
git clone https://github.com/mahsumaktas/ratchet.git
cd ratchet
bash install.sh

# Go to your project
cd ~/your-project

# Start Claude Code and run
claude
> /autoresearch            # general improvement
> /autoresearch fix 20     # fix 20 lint/type errors
> /autoresearch security   # security audit
```

Or just tell Claude naturally:
```
> projeyi iyileştir
> uyurken çalış
> analyze and improve this codebase
```

## Features

### 6 Modes

| Mode | Command | What it does |
|------|---------|-------------|
| **run** | `/autoresearch` | General improvement: bugs, lint, types, dead code |
| **fix** | `/autoresearch fix [N]` | Drive lint/type/test errors to zero |
| **debug** | `/autoresearch debug` | Scientific bug hunting: reproduce → 5 Whys → TDD fix |
| **security** | `/autoresearch security` | OWASP Top 10 + STRIDE threat scan |
| **predict** | `/autoresearch predict` | 5-persona analysis (no changes, just prioritized findings) |
| **plan** | `/autoresearch plan` | Interactive wizard → frozen metric config |

### Enforcement Hooks

Unlike markdown-only instructions, Ratchet uses real bash scripts that **mechanically enforce** the rules:

| Hook | Type | What it enforces |
|------|------|-----------------|
| `ar-state-enforcer.sh` | PreToolUse | Blocks edits outside MAKE_CHANGE state, blocks commits outside COMMIT state |
| `ar-boundary-guard.sh` | PreToolUse | Blocks edits to `never_touch` files (*.lock, node_modules, .env, etc.) |
| `ar-metrics-collector.sh` | PostToolUse | Auto-runs frozen metrics + guard + decision engine after every edit |
| `ar-session-restore.sh` | SessionStart | Restores state after Claude Code restart |
| `ar-compact-inject.sh` | PostCompact | Injects state after context compaction |
| `ar-stop-summary.sh` | Stop | Shows progress summary + triggers self-review |

**Performance:** When Ratchet is not active, all hooks exit in <1ms (single file existence check).

### Comprehensive Logging (v2)

Every hook call, every experiment, every decision is logged to project-local JSONL files:

```
.autoresearch/logs/
├── events.jsonl        — hook-level micro events (state transitions, boundary checks, guard runs)
├── experiments.jsonl    — full experiment records (metrics before/after, decision, strategy, duration)
└── insights.jsonl       — self-review learnings (accumulated across sessions)
```

Log rotation: `events.jsonl` auto-rotates at 5MB. Experiments and insights are preserved for analysis.

### Self-Review Engine (v2)

Ratchet analyzes its own performance and auto-adjusts configuration:

| Trigger | When | What it does |
|---------|------|-------------|
| **Session end** | Every stop | Analyzes all experiments, detects patterns |
| **Threshold** | 5 consecutive discards or every 20 experiments | Mid-session course correction |
| **Manual** | `/autoresearch review` | On-demand analysis |

**Auto-detected patterns:**

| Pattern | Action |
|---------|--------|
| Strategy < 10% success (5+ experiments) | Remove from rotation |
| File with 3+ consecutive failures | Add to `never_touch` |
| Last 10 experiments all discarded (local minimum) | Reset strategies + add `discovery` |
| Strategy > 70% success | Prioritize (move to front) |

**Safety:** Self-review can modify `strategy_rotation` and `never_touch`, but **never** touches `guard_command`, `frozen_commands`, `mode`, or `max_experiments`. Config backup taken before every change.

### State Machine

Every experiment follows a strict state machine. Invalid transitions are impossible:

```
BOOTSTRAP → SELECT_TARGET → READ_FILE → MAKE_CHANGE → VALIDATE → DECIDE
                 ↑                                                   |
                 |                                          COMMIT ←─┤ (KEEP)
                 |                                          REVERT ←─┘ (DISCARD)
                 |                                            |
                 └──────────── LOG ←──────────────────────────┘
```

### Guard Commands

Main metrics measure improvement. Guard commands prevent regression:

```
Optimize lint → lint errors decrease ✓
But guard (npm test) fails → DISCARD ✗
```

The guard ensures you never break tests while fixing lint, never break the build while adding types.

### Cross-run Learning (v2.1)

Ratchet remembers what worked and what didn't across sessions:

```
.autoresearch/lessons.jsonl
```

- **50-entry cap** with FIFO eviction
- **30-day time-decay** — old lessons auto-pruned at bootstrap
- **Auto-populated** — KEEP decisions record strategy + file + reason
- **Loaded into CHECKPOINT.md** — Claude sees previous learnings on restart

### Token & Cost Tracking (v2.1)

Track spending per ratchet session:

```bash
# During session — auto-tracked per experiment
# At session end — summary in stop hook:
# [RATCHET] 12 experiments (8 kept / 4 discarded) | Cost: 45K tokens, ~$0.32

# Budget enforcement:
# Set in config: "max_budget_usd": 5.00
# Ratchet stops when budget exceeded
```

### Environment Probing (v2.1)

At bootstrap, `ar-probe.sh` auto-detects:

| Category | Detected |
|----------|----------|
| Languages | Node.js, TypeScript, Python, Rust, Go, Ruby, Java, Shell |
| Test runners | jest, vitest, mocha, pytest, cargo test, go test |
| Linters | eslint, biome, ruff, clippy, go vet, rubocop |
| Type checkers | tsc, mypy, pyright |
| Frameworks | Next.js, Nuxt, Vite, Angular, Svelte, Django, Flask |
| CI | GitHub Actions, GitLab CI, Jenkins, CircleCI |
| Monorepo | lerna, pnpm workspaces, Cargo workspaces, nx |

Results saved to `state.json` as `environment` field — used for smarter strategy selection.

### Mechanical Decision Engine

The keep/discard decision is made by `ar-decide.sh` — a deterministic script, not an LLM judgment:

| Metrics | Guard | Decision |
|---------|-------|----------|
| Improved | PASS | **KEEP** |
| Same, code shorter | PASS | **KEEP** |
| Same, code same size | PASS | **KEEP** |
| Same, code longer | PASS | **DISCARD** |
| All errored | Any | **DISCARD** |
| Improved | FAIL | **DISCARD** |
| Worsened | Any | **DISCARD** |

Code size is measured via `git diff --stat` (insertions minus deletions) — only checked when all metrics are unchanged.

### Context-Reset Proof

Ratchet survives Claude Code restarts and context compaction:
- `state.json` — machine state, persisted to disk after every transition
- `CHECKPOINT.md` — self-contained document for zero-context resume
- `SessionStart` hook — auto-restores state on restart
- `PostCompact` hook — auto-injects state after compaction

### Strategy Rotation

When stuck (5 consecutive discards), Ratchet automatically switches strategy:

```
default → low-hanging-fruit → deep-refactor → security-sweep → dead-code-cleanup → discovery-driven
```

After 10 consecutive discards: stop and summarize.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    SKILL.md (Brain)                      │
│         Instructions Claude reads and follows            │
└──────────────────────┬──────────────────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
    ┌────▼────┐  ┌─────▼─────┐  ┌───▼────┐
    │  Hooks  │  │  Scripts  │  │ State  │
    │(Muscle) │  │ (Organs)  │  │(Memory)│
    └────┬────┘  └─────┬─────┘  └───┬────┘
         │             │             │
  PreToolUse:     ar-init.sh    .autoresearch/
  - state-enforcer ar-state.sh    state.json
  - boundary-guard ar-metrics.sh   results.tsv
  PostToolUse:    ar-guard.sh    CHECKPOINT.md
  - metrics-collector ar-decide.sh  metrics/
  SessionStart:   ar-report.sh
  - session-restore ar-webhook.sh
  PostCompact:    ar-config.sh
  - compact-inject
```

**Brain** (SKILL.md) can forget. **Muscles** (hooks) cannot — they run on every tool call, mechanically enforcing rules.

## Configuration

Create `.autoresearch/config.json` in your project root (optional — sensible defaults used if absent):

```json
{
  "mode": "run",
  "never_touch": ["*.lock", "node_modules/**", ".env*", "migrations/**"],
  "guard_command": "npm test",
  "parallel_workers": 1,
  "max_experiments": null,
  "notify_webhook": "https://hooks.slack.com/services/...",
  "consecutive_discard_limit": 5,
  "hard_stop_discard_limit": 10,
  "validator_interval": 5,
  "auto_checkpoint_interval": 3
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `mode` | `"run"` | Operating mode: run, fix, debug, security, predict, plan |
| `never_touch` | common patterns | Glob patterns for files that must never be modified |
| `guard_command` | test command | Command that must always pass (prevents regressions) |
| `parallel_workers` | `1` | Number of parallel experiment workers |
| `max_experiments` | `null` | Max experiments before stopping (null = infinite) |
| `notify_webhook` | `""` | Slack/Discord webhook URL for notifications |
| `consecutive_discard_limit` | `5` | Discards before strategy rotation |
| `hard_stop_discard_limit` | `10` | Discards before full stop |
| `validator_interval` | `5` | Run validator subagent every N experiments |
| `auto_checkpoint_interval` | `3` | Update CHECKPOINT.md every N experiments |

## Output Files

After running, you'll find in `.autoresearch/`:

| File | Purpose |
|------|---------|
| `state.json` | Live state machine (experiment count, metrics, strategy) |
| `results.tsv` | Full experiment log (exp, commit, metrics, decision, file, description) |
| `CHECKPOINT.md` | Self-contained resume document (context, progress, decisions, discoveries) |
| `NOTES.md` | Free-form observations |
| `SUMMARY.md` | Final report (generated at completion) |
| `ALERT.md` | Critical issues requiring human attention |
| `metrics/` | Baseline, latest, and history of all metric runs |
| `logs/events.jsonl` | Hook-level event log (v2) |
| `logs/experiments.jsonl` | Experiment-level decision log (v2) |
| `logs/insights.jsonl` | Self-review findings and actions (v2) |

See [examples/sample-output/](examples/sample-output/) for realistic examples.

## How It Works

1. **Bootstrap** — Detect project type, establish frozen metrics, create git branch
2. **Select Target** — Choose one file based on mode-specific priority (most errors, security risk, etc.)
3. **Read & Change** — Read the file, make exactly one atomic improvement
4. **Validate** — Hook auto-runs frozen metrics + guard command + decision engine
5. **Keep or Discard** — Deterministic decision: metrics improved + guard passed = KEEP, else DISCARD
6. **Log** — Update results.tsv, state.json, CHECKPOINT.md
7. **Repeat** — Until stopped or experiment limit reached

Every KEEP is a git commit. Every DISCARD is a `git checkout --`. The branch only moves forward.

## Inspiration

Ratchet combines ideas from:

- [**Karpathy's autoresearch**](https://github.com/karpathy/autoresearch) — Frozen metrics + ratchet philosophy
- [**uditgoenka/autoresearch**](https://github.com/uditgoenka/autoresearch) — Subcommands, guard commands, git-as-memory
- [**OpenAI Codex Execution Plans**](https://developers.openai.com/cookbook/articles/codex_exec_plans) — CHECKPOINT.md pattern, decision log
- [**barnum**](https://github.com/barnum-circus/barnum) — State machine enforcement, task-emits-task
- [**ralphy**](https://github.com/michaelshimeles/ralphy) — Parallel worktrees, boundary rules, webhook notifications
- [**subagent-orchestration**](https://skills.sh/dimitrigilbert/ai-skills/subagent-orchestration) — Validator subagent separation

## FAQ

**Q: Does this work with any language?**
A: Yes. Ratchet auto-detects Node.js, Python, Rust, and Go projects. For other languages, create `.autoresearch/config.json` with your test/lint/build commands.

**Q: What happens if Claude Code crashes mid-experiment?**
A: State is persisted to disk after every transition. On restart, the `SessionStart` hook restores context automatically.

**Q: Can I run this overnight?**
A: Yes. Set `max_experiments` in config or let it run until you stop it. Add a `notify_webhook` to get Slack/Discord notifications.

**Q: Does this slow down normal Claude Code usage?**
A: No. When Ratchet is not active, all hooks check a single file existence (`/tmp/ar-active-$PPID.txt`) and exit in <1ms.

**Q: What if it makes my code worse?**
A: Impossible by design. Every change is measured against frozen metrics. If metrics worsen, the change is discarded. The guard command prevents regressions in critical areas (like tests).

## Uninstall

```bash
bash ~/.claude/skills/autoresearch/uninstall.sh
```

Removes hooks, scripts, and settings.json entries. Project data (`.autoresearch/`) is preserved.

## Requirements

- [Claude Code](https://claude.com/claude-code) (CLI)
- `bash` 4+
- `python3` 3.12+
- `git`

## Changelog

### v3.0 (2026-03-24)
- **Parallel worktree experiments:** Run N hypotheses simultaneously in isolated git worktrees, compare results, pick the best (`ar-parallel.sh run 3`)
- **CI/CD exec mode:** Non-interactive mode with JSON output and exit codes for pipeline integration (`ar-ci.sh --max-experiments 10 --budget 5.00`)
- **GitHub Actions workflow:** Ready-to-use `.github/workflows/ratchet.yml` with weekly schedule + manual dispatch
- **Benchmark suite:** Performance benchmarks + stress tests (`tests/benchmark.sh`) — all components <15ms/call
- **Stress tested:** 100x ar_log, 50x lessons, 50x cost tracking — 100% success rate

### v2.1 (2026-03-24)
- **Cross-run lessons:** Persistent `lessons.jsonl` — learnings carry forward across sessions with 50-entry cap and 30-day time-decay
- **Token/cost tracking:** Per-session token count + USD cost estimate with budget limits (`ar-cost.sh check <budget>`)
- **Environment probing:** Auto-detect languages, test runners, linters, frameworks, CI, monorepo status at bootstrap
- **Validator subagent:** Haiku-powered read-only verification every 5 experiments (SKILL.md instruction)
- **Incremental metrics:** Only lint affected files instead of full suite (faster feedback loop)

### v2 (2026-03-24)
- **Logging:** 3-tier JSONL logging (events, experiments, insights) with auto-rotation
- **Self-review:** Autonomous pattern detection + config optimization (strategy pruning, file blocking, local minimum escape)
- **Bug fix:** Boundary guard now supports `**` recursive globs (`node_modules/**` works correctly)
- **Bug fix:** Shell injection in `ar-init.sh` replaced with `os.environ` pattern
- **Bug fix:** Decision engine handles all-error metrics (DISCARD) and checks code size when metrics unchanged
- **Bug fix:** `ar-metrics-collector.sh` pipe/heredoc stdin conflict resolved
- **New:** `uninstall.sh` for clean removal
- **New:** Integration test suite (`tests/test-ratchet.sh`)
- **Improved:** `ar_state_get_multi` used for batch state reads (fewer python3 forks)

### v1 (2026-03-23)
- Initial release: 6 modes, state machine, enforcement hooks, deterministic decisions

## License

[MIT](LICENSE)

---

Built with Claude Code. Tested on real codebases. Ships improvements, not promises.

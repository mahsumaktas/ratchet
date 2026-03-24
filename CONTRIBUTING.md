# Contributing to Ratchet

Thanks for your interest in contributing!

## How to Contribute

### Bug Reports
- Open an issue with steps to reproduce
- Include your Claude Code version and OS
- Attach relevant log output from `~/.claude/logs/autoresearch.jsonl`

### Feature Requests
- Open an issue describing the use case
- Explain why existing features don't cover it

### Pull Requests
1. Fork the repo
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test the install script: `bash install.sh`
5. Test hooks: `bash scripts/ar-state.sh get` (should work in a git repo)
6. Commit with clear messages
7. Open a PR against `main`

## Code Style

### Shell Scripts
- Use `#!/usr/bin/env bash`
- `set -euo pipefail` at the top
- Source `_lib.sh` for shared functions
- Fast exit pattern: `[ -f "$AR_ACTIVE_FLAG" ] || exit 0`
- Use `python3 -c` for JSON operations
- Comments in English

### Hook Scripts
- PreToolUse hooks: `exit 2` = block, `exit 0` = allow
- PostToolUse hooks: always `exit 0`
- Emit messages via `echo '{"systemMessage":"..."}'`
- Log to `~/.claude/logs/autoresearch.jsonl`
- Key state files by `$PPID` in `/tmp/`

### SKILL.md / References
- Written in English (Turkish in user-facing messages)
- Clear, imperative instructions
- Tables for decision matrices

## Testing

```bash
# Verify all scripts have valid bash syntax
for f in scripts/*.sh hooks/*.sh; do bash -n "$f" && echo "OK: $f"; done

# Test state machine transitions
cd /tmp && git init test-ratchet && cd test-ratchet
bash ~/Projects/ratchet/scripts/ar-init.sh run
bash ~/Projects/ratchet/scripts/ar-state.sh info
bash ~/Projects/ratchet/scripts/ar-state.sh transition READ_FILE
bash ~/Projects/ratchet/scripts/ar-state.sh transition MAKE_CHANGE
```

## Architecture

See [README.md](README.md#architecture) for the full architecture overview.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

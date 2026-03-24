#!/usr/bin/env bash
# install.sh — One-command Ratchet installer for Claude Code
# Usage: bash install.sh
# Or:    curl -fsSL https://raw.githubusercontent.com/mahsumaktas/ratchet/main/install.sh | bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
SKILLS_DIR="${CLAUDE_DIR}/skills/autoresearch"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

echo "=== Ratchet Installer ==="
echo ""

# --- Pre-checks ---
if [ ! -d "$CLAUDE_DIR" ]; then
  echo "ERROR: ~/.claude directory not found. Is Claude Code installed?" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required." >&2
  exit 1
fi

# --- Create directories ---
mkdir -p "$HOOKS_DIR" "$SKILLS_DIR/references" "$SKILLS_DIR/scripts"
echo "[1/5] Directories created."

# --- Copy scripts ---
cp "$REPO_DIR/scripts/"* "$SKILLS_DIR/scripts/" 2>/dev/null || true
chmod +x "$SKILLS_DIR/scripts/"*.sh 2>/dev/null || true
echo "[2/5] Scripts installed to $SKILLS_DIR/scripts/"

# --- Copy hooks ---
cp "$REPO_DIR/hooks/"* "$HOOKS_DIR/" 2>/dev/null || true
chmod +x "$HOOKS_DIR/ar-"*.sh 2>/dev/null || true
echo "[3/5] Hooks installed to $HOOKS_DIR/"

# --- Copy skill files ---
cp "$REPO_DIR/skills/autoresearch/SKILL.md" "$SKILLS_DIR/SKILL.md"
cp "$REPO_DIR/skills/autoresearch/references/"*.md "$SKILLS_DIR/references/" 2>/dev/null || true
echo "[4/5] Skill files installed to $SKILLS_DIR/"

# --- Update settings.json ---
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "{}" > "$SETTINGS_FILE"
fi

# Check if ratchet hooks are already installed
if grep -q "ar-state-enforcer" "$SETTINGS_FILE" 2>/dev/null; then
  echo "[5/5] Hooks already registered in settings.json (skipping)."
else
  # Inject hook entries into settings.json
  python3 << 'INJECT_HOOKS'
import json, sys, os

settings_path = os.path.expanduser("~/.claude/settings.json")

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# PreToolUse hooks
pre = hooks.setdefault("PreToolUse", [])
pre.append({
    "matcher": "Write|Edit|MultiEdit|Bash",
    "hooks": [{"type": "command", "command": "bash $HOME/.claude/hooks/ar-state-enforcer.sh", "timeout": 3}]
})
pre.append({
    "matcher": "Write|Edit|MultiEdit",
    "hooks": [{"type": "command", "command": "bash $HOME/.claude/hooks/ar-boundary-guard.sh", "timeout": 3}]
})

# PostToolUse hooks
post = hooks.setdefault("PostToolUse", [])
post.append({
    "matcher": "Write|Edit|MultiEdit",
    "hooks": [{"type": "command", "command": "bash $HOME/.claude/hooks/ar-metrics-collector.sh", "timeout": 30}]
})

# SessionStart hooks
session = hooks.setdefault("SessionStart", [])
session.append({
    "matcher": "startup|resume",
    "hooks": [{"type": "command", "command": "bash $HOME/.claude/hooks/ar-session-restore.sh", "timeout": 5}]
})

# PostCompact hooks
compact = hooks.setdefault("PostCompact", [])
compact.append({
    "hooks": [{"type": "command", "command": "bash $HOME/.claude/hooks/ar-compact-inject.sh", "timeout": 5}]
})

# Stop hooks
stop = hooks.setdefault("Stop", [])
stop.append({
    "hooks": [{"type": "command", "command": "bash $HOME/.claude/hooks/ar-stop-summary.sh", "timeout": 10}]
})

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print("[5/5] Hook entries added to settings.json.")
INJECT_HOOKS
fi

echo ""
echo "=== Ratchet installed successfully! ==="
echo ""
echo "Usage:"
echo "  cd your-project/"
echo "  claude"
echo "  > /autoresearch           # default run mode"
echo "  > /autoresearch fix 20    # fix mode, 20 experiments"
echo "  > /autoresearch security  # security audit"
echo ""
echo "Or just say: 'projeyi iyilestir', 'uyurken calis', 'autoresearch'"
echo ""

# --- Verify ---
echo "Verification:"
errors=0
for script in ar-state-enforcer.sh ar-boundary-guard.sh ar-metrics-collector.sh ar-session-restore.sh ar-compact-inject.sh ar-stop-summary.sh; do
  if [ -x "$HOOKS_DIR/$script" ]; then
    echo "  OK  $script"
  else
    echo "  FAIL  $script"
    errors=$((errors + 1))
  fi
done

for script in _lib.sh ar-init.sh ar-state.sh ar-metrics.sh ar-guard.sh ar-decide.sh ar-report.sh ar-config.sh ar-webhook.sh; do
  if [ -f "$SKILLS_DIR/scripts/$script" ]; then
    echo "  OK  scripts/$script"
  else
    echo "  FAIL  scripts/$script"
    errors=$((errors + 1))
  fi
done

if [ "$errors" -eq 0 ]; then
  echo ""
  echo "All checks passed."
else
  echo ""
  echo "WARNING: $errors checks failed." >&2
fi

#!/usr/bin/env bash
# uninstall.sh — Clean removal of Ratchet from Claude Code
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

echo "=== Ratchet Uninstaller ==="

# Backup settings.json
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.pre-uninstall" 2>/dev/null || true

  # Remove ratchet hook entries from settings.json
  AR_SETTINGS_PATH="$SETTINGS" python3 -c "
import json, os
settings_path = os.environ['AR_SETTINGS_PATH']
with open(settings_path) as f:
    settings = json.load(f)
hooks = settings.get('hooks', {})
for event_type in list(hooks.keys()):
    entries = hooks[event_type]
    if isinstance(entries, list):
        hooks[event_type] = [e for e in entries
                             if not (isinstance(e, dict) and 'ar-' in e.get('command', ''))]
        if not hooks[event_type]:
            del hooks[event_type]
settings['hooks'] = hooks
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
print('settings.json cleaned: ratchet hooks removed')
" 2>/dev/null || echo "WARNING: Could not clean settings.json"
fi

# Remove hook files
for f in "$HOME"/.claude/hooks/ar-*.sh; do
  [ -f "$f" ] && rm "$f" && echo "Removed: $f"
done

# Remove skill directory
if [ -d "$HOME/.claude/skills/autoresearch" ]; then
  rm -rf "$HOME/.claude/skills/autoresearch"
  echo "Removed: ~/.claude/skills/autoresearch/"
fi

echo ""
echo "Ratchet uninstalled successfully."
echo "Project data (.autoresearch/) preserved in your projects."
[ -f "$SETTINGS.bak.pre-uninstall" ] && echo "Backup: $SETTINGS.bak.pre-uninstall"

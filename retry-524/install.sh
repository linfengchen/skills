#!/usr/bin/env bash
# Install the retry-524 skill + the gateway-timeout detection hook into ~/.claude,
# and idempotently wire the hook into settings.json (PostToolUse + PostToolUseFailure).
#
# Usage:  ./install.sh
# Re-running is safe — it replaces its own entries instead of duplicating them.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKILL_SRC="$SRC_DIR/SKILL.md"
HOOK_SRC="$SRC_DIR/hooks/detect-gateway-timeout.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_DEST="$CLAUDE_DIR/hooks/detect-gateway-timeout.sh"
SKILL_DEST_DIR="$CLAUDE_DIR/skills/retry-524"

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required. Install it first (brew install jq / apt-get install jq)." >&2
  exit 1
}

mkdir -p "$SKILL_DEST_DIR" "$CLAUDE_DIR/hooks"

# 1) Skill definition
cp "$SKILL_SRC" "$SKILL_DEST_DIR/SKILL.md"
echo "installed skill  -> $SKILL_DEST_DIR/SKILL.md"

# 2) Hook script
cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "installed hook   -> $HOOK_DEST"

# 3) Wire the hook into settings.json (create the file if missing). Idempotent:
#    any existing entry pointing at this hook is dropped before re-adding.
CMD="\"\$HOME/.claude/hooks/detect-gateway-timeout.sh\""
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

tmp="$(mktemp)"
jq --arg cmd "$CMD" '
  def wire(ev):
    .hooks[ev] = (
      ((.hooks[ev] // []) | map(select(any(.hooks[]?; .command? == $cmd) | not)))
      + [ { matcher: "*", hooks: [ { type: "command", command: $cmd, statusMessage: "Checking upstream status" } ] } ]
    );
  .hooks = (.hooks // {})
  | wire("PostToolUse")
  | wire("PostToolUseFailure")
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "wired hooks      -> $SETTINGS (PostToolUse + PostToolUseFailure)"

echo
echo "Done. If the hook does not fire immediately, open Claude Code's /hooks menu"
echo "once (it reloads config) or restart the session."

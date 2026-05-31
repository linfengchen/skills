# retry-524 — Gateway-Timeout Recovery (skill + auto-trigger hook)

Handles HTTP **524** and equivalent gateway / upstream timeouts (522, 502, 504,
"gateway time-out", "upstream request timeout") with a fixed recovery procedure:

> **Retry the same operation once. If it times out again, stop retrying and split
> the work into several smaller independent subagents run in parallel, then merge.**

This package has two parts that work together:

| Part | File | Role |
|------|------|------|
| **Skill** | `SKILL.md` | The recovery procedure Claude follows. Model-invoked (matches on 524/timeout) or user-invoked via `/retry-524`. |
| **Hook** | `hooks/detect-gateway-timeout.sh` | A `PostToolUse` / `PostToolUseFailure` hook that scans tool results for a timeout signature and **injects a reminder** so the skill fires reliably instead of relying on Claude noticing. |

The skill alone is model-driven (Claude has to recognize the situation). Adding
the hook makes it **near-certain to trigger**: whenever a network tool result
contains a gateway-timeout signature, the hook feeds a reminder back to Claude.

## Install

```bash
./install.sh
```

Requirements: `jq`, `bash`, and Claude Code using `~/.claude`.

The installer:
1. copies `SKILL.md` → `~/.claude/skills/retry-524/SKILL.md`
2. copies the hook → `~/.claude/hooks/detect-gateway-timeout.sh` (chmod +x)
3. idempotently wires it into `~/.claude/settings.json` under `PostToolUse` and
   `PostToolUseFailure` (existing settings and other hooks are preserved).

Re-running `install.sh` is safe — it replaces only its own hook entries.

After installing, if the hook doesn't fire right away, open Claude Code's
`/hooks` menu once (reloads config) or restart the session.

## How the hook avoids false positives

- It inspects **only `tool_response`**, never `tool_input`, so prompt or command
  text that merely mentions these codes never triggers it.
- It only runs for **network-capable tools** (`WebFetch`, `WebSearch`, `Bash`,
  `mcp__*`) — file reads/edits can't produce a gateway timeout.
- It matches **specific HTTP signatures** (explicit phrases, or a 5xx code
  adjacent to an HTTP/error keyword or gateway phrase), not a loose
  "number near a word", so paths like `retry-524/...gateway-timeout` don't match.

On a match it prints the reminder to stderr and exits 2, which Claude Code feeds
back into the model as context.

## Uninstall

Remove the two files and delete the `PostToolUse`/`PostToolUseFailure` entries
that reference `detect-gateway-timeout.sh` from `~/.claude/settings.json`.

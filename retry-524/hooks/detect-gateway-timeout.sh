#!/usr/bin/env bash
# Detect gateway / upstream-timeout signatures (524-class) in a tool result and,
# if found, remind Claude to follow the retry-524 skill.
#
# Wired to PostToolUse + PostToolUseFailure in ~/.claude/settings.json.
# Reads the hook JSON on stdin. Inspects ONLY .tool_response — never tool_input —
# so it never fires on prompt/command text that merely mentions these codes.
# On a match: prints the reminder to stderr and exits 2, which feeds stderr back
# to Claude as context.
set -uo pipefail

payload="$(cat)"

# Gateway/upstream timeouts only originate from network I/O. Restrict to
# network-capable tools so editing/reading files that merely MENTION these
# phrases (e.g. this hook's own docs) never false-positives.
tool="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
case "$tool" in
  WebFetch|WebSearch|Bash) ;;
  mcp__*) ;;
  *) exit 0 ;;
esac

resp="$(printf '%s' "$payload" | jq -r '.tool_response | tostring' 2>/dev/null || true)"
[ -z "$resp" ] || [ "$resp" = "null" ] && exit 0

# Match only clear HTTP gateway-timeout signatures:
#  - explicit phrases (gateway time-out / upstream request timeout / bad gateway / service unavailable)
#  - a 5xx code immediately preceded by an HTTP/error keyword (error|status|code|http|api error)
#  - a 5xx status line immediately followed by a gateway/timeout phrase
# Deliberately NOT a loose "number near word" match, so paths like
# "retry-524/hooks/detect-gateway-timeout" never false-positive.
if printf '%s' "$resp" | grep -qiE 'gateway ?time-?out|upstream request timeout|bad gateway|service (temporarily )?unavailable|(error|err|status|code|https?/?[0-9.]*|api error)[ :]+(502|503|504|520|521|522|523|524)\b|\b(502|503|504|520|521|522|523|524):? (a timeout|bad gateway|gateway|service|timeout)'; then
  echo "⚠️ Gateway/upstream timeout (524-class) detected in the tool result. Follow the retry-524 skill: retry this SAME operation exactly once; if it times out again, STOP retrying and split the work into several smaller independent subagents run in parallel, then merge their results. Do not report this as a hard failure before doing so." >&2
  exit 2
fi
exit 0

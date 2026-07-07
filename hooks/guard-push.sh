#!/usr/bin/env bash
# autoDev — push guard (PreToolUse hook). Blocks a Bash `git push` of the default
# branch, and blocks ALL pushes when review.delivery=local_diff — mirroring the old
# .git/hooks/pre-push guard without ever touching the repo's own git config. Reads
# .autodev/deployment.json from the tool call's cwd; fails open (allows) if autoDev
# isn't configured there. Only guards pushes made through Claude Code — a human's own
# terminal is never affected (there is no hook installed outside this plugin).
set -uo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL" == "Bash" ]] || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
echo "$CMD" | grep -qE '(^|;|&&|\|)\s*git\s+push\b' || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
CONFIG="$CWD/.autodev/deployment.json"
[[ -f "$CONFIG" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

DEFAULT_BRANCH=$(jq -r '.repo.default_branch // "main"' "$CONFIG")
DELIVERY=$(jq -r '.review.delivery // "draft_pr"' "$CONFIG")

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

if [[ "$DELIVERY" == "local_diff" ]]; then
  deny "autoDev: review.delivery=local_diff (LOCAL-ONLY mode) — never push; present a local diff instead (reference/manual.md ▸ Delivery mode)."
fi

if echo "$CMD" | grep -qE "(refs/heads/${DEFAULT_BRANCH}\b|[[:space:]:]${DEFAULT_BRANCH}([[:space:]:]|\$))"; then
  deny "autoDev: only humans merge '${DEFAULT_BRANCH}' (Gate 2 + branch protection) — the engine never pushes it."
fi

exit 0

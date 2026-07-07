#!/usr/bin/env bash
# autoDev — ambient SessionStart signal. ONE line, only if this repo is configured
# (.autodev/deployment.json present) — never injects the manual, never forces a
# workflow. /autodev:new and /autodev:loop read the manual themselves when invoked.
set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
CONFIG="$CWD/.autodev/deployment.json"
[[ -f "$CONFIG" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

CLIENT=$(jq -r '.client_name // "this deployment"' "$CONFIG")
KIND=$(jq -r '.tracker.kind // "linear"' "$CONFIG")
COUNT_TXT=""
if [[ "$KIND" == "local" ]]; then
  N=$(find "$CWD/.autodev/board" -maxdepth 1 -name '*.json' ! -name '_*' ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
  COUNT_TXT=" — ${N:-0} stories on the board"
fi

MSG="⚙️ autoDev is configured here (${CLIENT}${COUNT_TXT}). Run \`/autodev:loop\` to continue, or \`/autodev:new\` to add work."
jq -n --arg c "$MSG" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'

#!/usr/bin/env bash
# autoDev — identity pointer at .claude/CLAUDE.md, the fallback for sessions where
# the SessionStart hook hasn't run yet (workspace trust not granted): CLAUDE.md
# auto-loads as memory, the hook does not. Rules: a TEAM-authored file here is NEVER
# touched; our own artifacts (a previous pointer, or the pre-plugin install.sh-era
# rulebook) are replaced; if the slot is empty we write the pointer.
#
# Usage: write-identity-pointer.sh <repo-path>
set -uo pipefail

REPO="${1:?usage: write-identity-pointer.sh <repo-path>}"
CONFIG="$REPO/.autodev/deployment.json"
[[ -f "$CONFIG" ]] || { echo "write-identity-pointer: no $CONFIG" >&2; exit 1; }

CLIENT=$(jq -r '.client_name // "this deployment"' "$CONFIG")
ASSISTANT=$(jq -r '.assistant_name // "Marj"' "$CONFIG")
PTR="$REPO/.claude/CLAUDE.md"

if [[ ! -f "$PTR" ]] || grep -qE "autoDev POINTER|— autoDev engine" "$PTR"; then
  mkdir -p "$REPO/.claude"
  cat > "$PTR" <<EOF
# $CLIENT — operated by autoDev (autoDev POINTER)

> This file is an **autoDev POINTER**, not your project docs — it exists so every
> session learns the engine identity even before the SessionStart hook is trusted.
> Replace it freely with your own CLAUDE.md; autoDev never overwrites a
> team-authored file in this slot.

This repository is operated by **autoDev**, a Claude Code plugin. You are
**$ASSISTANT**, its operator concierge — not a free-roaming assistant. Run
\`/autodev:loop\` to check the next step, or \`/autodev:new\` to capture new work.
Route everything else through the board and the two human gates.
EOF
  echo "✓ wrote .claude/CLAUDE.md identity pointer (hook-less sessions still load the engine identity)"
else
  echo "✓ left your team-authored .claude/CLAUDE.md untouched (identity rides the SessionStart hook + /autodev:loop)"
fi

#!/usr/bin/env bash
# autoDev — migrate a repo from the old VENDORED install (pre-plugin: engine files
# committed into the repo) to the plugin. Removes ONLY artifacts the old installer
# wrote (verified by content markers, never by filename alone), backs everything up
# to .autodev/backup-vendored/, restores team files the old installer displaced, and
# preserves all state (.autodev/deployment.json, board/, conventions.md, metrics).
# Idempotent: a second run finds nothing and says so. Run by /autodev:init (and safe
# to run by hand): scripts/migrate-vendored.sh [repo_path]
set -uo pipefail

REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
BK="$REPO/.autodev/backup-vendored"
moved=0
note() { printf '  %s\n' "$1"; }
stash() { # <path-relative-to-repo>  — move to backup, preserving structure
  local rel="$1"
  [[ -e "$REPO/$rel" ]] || return 0
  mkdir -p "$BK/$(dirname "$rel")"
  mv "$REPO/$rel" "$BK/$rel"
  moved=$((moved+1))
  note "→ backed up + removed: $rel"
}

echo "vendored-install migration scan: $REPO"

# 1. The old engine manual + skills + command (ours iff they carry engine markers).
stash ".claude/autodev.md"
for f in intake prd breakdown devloop merge-verify _story-template; do
  p="$REPO/.claude/skills/$f.md"
  [[ -f "$p" ]] && grep -qi "autodev" "$p" && stash ".claude/skills/$f.md"
done
[[ -d "$REPO/.claude/skills" ]] && rmdir "$REPO/.claude/skills" 2>/dev/null || true
p="$REPO/.claude/commands/devloop.md"
[[ -f "$p" ]] && grep -qi "autoDev dev engine" "$p" && stash ".claude/commands/devloop.md"
[[ -d "$REPO/.claude/commands" ]] && rmdir "$REPO/.claude/commands" 2>/dev/null || true

# 2. The vendored scripts directory (entirely ours) — both generations.
[[ -d "$REPO/scripts/autodev" ]] && { mkdir -p "$BK/scripts"; mv "$REPO/scripts/autodev" "$BK/scripts/autodev"; moved=$((moved+1)); note "→ backed up + removed: scripts/autodev/"; }
[[ -d "$REPO/scripts" ]] && rmdir "$REPO/scripts" 2>/dev/null || true
[[ -d "$REPO/.autodev/engine" ]] && { mkdir -p "$BK/.autodev"; mv "$REPO/.autodev/engine" "$BK/.autodev/engine"; moved=$((moved+1)); note "→ backed up + removed: .autodev/engine/ (new-style vendored engine)"; }
for c in init new loop; do
  p="$REPO/.claude/commands/autodev-$c.md"
  [[ -f "$p" ]] && grep -qi "autodev" "$p" && stash ".claude/commands/autodev-$c.md"
done

# 3. settings.json: ours -> restore the team's backed-up one (or remove ours).
S="$REPO/.claude/settings.json"
if [[ -f "$S" ]] && grep -q "autoDev headless permissions" "$S"; then
  stash ".claude/settings.json"
  if [[ -f "$S.pre-autodev" ]]; then
    mv "$S.pre-autodev" "$S"
    note "→ restored team settings from settings.json.pre-autodev"
  fi
elif [[ -f "$S" ]] && command -v jq >/dev/null && jq -e '[.hooks[]?[]?.hooks[]?.command // empty] | any(contains("scripts/autodev/") or contains(".autodev/engine"))' "$S" >/dev/null 2>&1; then
  # team-authored settings carrying our hooks (old hand-merge, or a new-style vendored
  # install's merge): surgically drop just OUR entries, keep everything of theirs
  mkdir -p "$BK"; cp "$S" "$BK/.claude-settings.json.before-hook-removal"
  jq '.hooks = ((.hooks // {}) | with_entries(.value |= (map(.hooks |= map(select((.command // "") | (contains("scripts/autodev/") or contains(".autodev/engine")) | not))) | map(select(.hooks | length > 0)))) | with_entries(select(.value | length > 0)))' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
  moved=$((moved+1)); note "→ removed our hooks from your settings.json (original copied to backup)"
fi

# 4. Our pre-push hook -> restore the chained team hook if we displaced one.
H="$REPO/.git/hooks/pre-push"
if [[ -f "$H" ]] && grep -q "autoDev pre-push" "$H"; then
  rm "$H"; moved=$((moved+1)); note "→ removed our .git/hooks/pre-push (the plugin's PreToolUse guard replaces it)"
  [[ -f "$REPO/.git/hooks/pre-push.pre-autodev" ]] && { mv "$REPO/.git/hooks/pre-push.pre-autodev" "$H"; note "→ restored your original pre-push hook"; }
fi

# 5. Our old CLAUDE.md artifacts (stale rulebook / pre-plugin pointer) -> current
# pointer. The CURRENT pointer names the /autodev: commands — leave it alone.
C="$REPO/.claude/CLAUDE.md"
if [[ -f "$C" ]] && grep -qE "autoDev POINTER|— autoDev engine" "$C" && ! grep -q "/autodev:" "$C"; then
  stash ".claude/CLAUDE.md"
  bash "$(dirname "${BASH_SOURCE[0]}")/write-identity-pointer.sh" "$REPO" >/dev/null 2>&1 || true
  note "→ replaced our old CLAUDE.md artifact with the current pointer"
fi

# 6. Old vendored ops copies (the plugin carries ops/ internally now).
[[ -d "$REPO/.autodev/ops" ]] && { mkdir -p "$BK/.autodev"; mv "$REPO/.autodev/ops" "$BK/.autodev/ops"; moved=$((moved+1)); note "→ backed up + removed: .autodev/ops/ (plugin ships these)"; }

if [[ $moved -eq 0 ]]; then
  echo "  ✓ no vendored install found — nothing to migrate"
else
  echo "  ✓ migrated: $moved artifact(s) moved to .autodev/backup-vendored/ (delete it once you're confident)"
  echo "  state preserved: .autodev/deployment.json · board/ · conventions.md · metrics.jsonl"
  echo "  ⚠ these removals are working-tree changes — review + commit them (e.g. 'chore: migrate autoDev vendored install → plugin')"
fi

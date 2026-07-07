#!/usr/bin/env bash
# autoDev smoke test — installs the engine into a synthetic client repo and asserts the
# contracts that have bitten us in real deployments. Run locally or in CI: tests/smoke.sh
set -uo pipefail
ENGINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }
check() { # <desc> <cmd...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}

# ---- synthetic client repo: team docs + foreign settings + team hook + MUI/codegen ----
TGT=$(mktemp -d); trap 'rm -rf "$TGT" "$CFG"' EXIT
git -C "$TGT" init -q
printf '# Team conventions\n- Commit directly to main for hotfixes.\n- Use the MUI theme.\n' > "$TGT/AGENTS.md"
mkdir -p "$TGT/.claude"; echo 'team rules' > "$TGT/.claude/CLAUDE.md"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$TGT/.claude/settings.json"
mkdir -p "$TGT/.git/hooks"; printf '#!/bin/sh\nexit 0\n' > "$TGT/.git/hooks/pre-push"; chmod +x "$TGT/.git/hooks/pre-push"
echo '{"dependencies":{"react":"18","@mui/material":"5"},"devDependencies":{"@graphql-codegen/cli":"5"}}' > "$TGT/package.json"
echo '{}' > "$TGT/tsconfig.json"; touch "$TGT/codegen.ts"

CFG=$(mktemp).json
jq '.client_name="SmokeCo" | .repo.local_path=$p' --arg p "$TGT" "$ENGINE/config/deployment.example.json" > "$CFG"

echo "install:"
if OUT=$(bash "$ENGINE/install.sh" "$CFG" 2>&1); then pass "install.sh exits 0"; else fail "install.sh exits 0"; echo "$OUT" | tail -5; fi

echo "render:"
check "autodev.md installed" test -f "$TGT/.claude/autodev.md"
check "no unrendered placeholders" bash -c "! grep -rl '{{' '$TGT/.claude' '$TGT/scripts/autodev'"
check "engine version stamped" jq -e '.engine.version and .engine.sha' "$TGT/.autodev/deployment.json"

echo "preservation (the AGENTS.md incident):"
check "team AGENTS.md untouched" grep -q "Use the MUI theme" "$TGT/AGENTS.md"
check "team .claude/CLAUDE.md untouched" grep -q "team rules" "$TGT/.claude/CLAUDE.md"
check "foreign settings backed up" grep -q "Bash(ls" "$TGT/.claude/settings.json.pre-autodev"
check "autoDev settings written" grep -q "autoDev headless" "$TGT/.claude/settings.json"
check "team pre-push hook chained" test -x "$TGT/.git/hooks/pre-push.pre-autodev"
check "AGENTS.md deny present" grep -q '"Edit(AGENTS.md)"' "$TGT/.claude/settings.json"

echo "conventions:"
check "codegen rule detected" grep -q "GraphQL code generation" "$TGT/.autodev/conventions.md"
check "MUI theme rule detected" grep -q "Material UI" "$TGT/.autodev/conventions.md"
check "comment rule present" grep -q "explain WHY" "$TGT/.autodev/conventions.md"

echo "session hook:"
check "emits valid JSON with the manual + Marj" bash -c \
  "CLAUDE_PROJECT_DIR='$TGT' bash '$TGT/scripts/autodev/session-init.sh' | jq -e '.hookSpecificOutput.additionalContext | contains(\"Marj\") and contains(\"operating manual\")'"

echo "pre-push guard (engine-only enforcement):"
REFS_FEAT="refs/heads/f a refs/heads/feature/x b"; REFS_MAIN="refs/heads/m a refs/heads/main b"
check "agent+draft_pr: feature push allowed" bash -c "cd '$TGT' && echo '$REFS_FEAT' | CLAUDECODE=1 .git/hooks/pre-push origin u"
check "agent+draft_pr: main push blocked"    bash -c "cd '$TGT' && ! (echo '$REFS_MAIN' | CLAUDECODE=1 .git/hooks/pre-push origin u)"
jq '.review.delivery="local_diff"' "$TGT/.autodev/deployment.json" > "$TGT/.autodev/t" && mv "$TGT/.autodev/t" "$TGT/.autodev/deployment.json"
check "agent+local_diff: all pushes blocked" bash -c "cd '$TGT' && ! (echo '$REFS_FEAT' | CLAUDECODE=1 .git/hooks/pre-push origin u)"
check "human: never blocked"                 bash -c "cd '$TGT' && echo '$REFS_MAIN' | env -u CLAUDECODE .git/hooks/pre-push origin u"

echo "docs conflict scan:"
check "flags 'commit directly to main'" bash -c "bash '$TGT/scripts/autodev/check-docs.sh' '$TGT' | grep -q 'only humans merge'"

echo "local tracker (git-native board):"
jq '.tracker.kind="local"' "$TGT/.autodev/deployment.json" > "$TGT/.autodev/t" && mv "$TGT/.autodev/t" "$TGT/.autodev/deployment.json"
TRK="$TGT/scripts/autodev/tracker.mjs"
LID=$(cd "$TGT" && node "$TRK" create-issue --title "Smoke story" --stage ready_for_ai_dev --labels ai-eligible 2>/dev/null)
check "create-issue returns an id" test -n "$LID"
check "move + note" bash -c "cd '$TGT' && node '$TRK' move '$LID' ai_development --note 'dev started' | grep -q 'AI Development'"
check "comment" bash -c "cd '$TGT' && node '$TRK' comment '$LID' 'progress'"
check "history recorded in issue file" bash -c "jq -e '.history | length >= 2' '$TGT/.autodev/board/$LID.json'"
check "board renders html" bash -c "cd '$TGT' && node '$TRK' board >/dev/null && test -f '$TGT/.autodev/board.html'"
check "tracker doctor ok" bash -c "cd '$TGT' && node '$TRK' doctor | grep -q 'local board'"

echo "identity pointer (hook-less fallback):"
# scenario A: the main TGT has a TEAM CLAUDE.md — must have been preserved (asserted
# above). scenario B: bare repo -> pointer written. C: our stale rulebook -> replaced.
T2=$(mktemp -d); git -C "$T2" init -q; echo '{}' > "$T2/package.json"
CFG2=$(mktemp).json; jq '.client_name="BareCo" | .repo.local_path=$p' --arg p "$T2" "$ENGINE/config/deployment.example.json" > "$CFG2"
bash "$ENGINE/install.sh" "$CFG2" >/dev/null 2>&1
check "bare repo gets the pointer" grep -q "autoDev POINTER" "$T2/.claude/CLAUDE.md"
check "pointer names the manual" grep -q "autodev.md" "$T2/.claude/CLAUDE.md"
printf '# BareCo — autoDev engine\nold stale rulebook\n' > "$T2/.claude/CLAUDE.md"
bash "$ENGINE/install.sh" "$CFG2" >/dev/null 2>&1
check "our stale rulebook is replaced (not treated as team file)" grep -q "autoDev POINTER" "$T2/.claude/CLAUDE.md"
rm -rf "$T2" "$CFG2"

echo
if [[ $FAIL -eq 0 ]]; then echo "smoke: PASS"; else echo "smoke: FAIL"; fi
exit $FAIL

#!/usr/bin/env bash
# autoDev smoke test — exercises the plugin's scripts and hooks directly against a
# synthetic client repo, asserting the contracts that have bitten us in real
# deployments. No Claude invocation (the commands themselves are prose, interpreted
# by Claude at runtime — not something a shell script can drive). Run: tests/smoke.sh
set -uo pipefail
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }
check() { # <desc> <cmd...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}

# ---- synthetic client repo: team docs + foreign settings + a pre-existing git hook + MUI/codegen ----
TGT=$(mktemp -d); trap 'rm -rf "$TGT"' EXIT
git -C "$TGT" init -q
printf '# Team conventions\n- Commit directly to main for hotfixes.\n- Use the MUI theme.\n' > "$TGT/AGENTS.md"
mkdir -p "$TGT/.claude"; echo 'team rules' > "$TGT/.claude/CLAUDE.md"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$TGT/.claude/settings.json"
mkdir -p "$TGT/.git/hooks"; printf '#!/bin/sh\nexit 0\n' > "$TGT/.git/hooks/pre-push"; chmod +x "$TGT/.git/hooks/pre-push"
echo '{"dependencies":{"react":"18","@mui/material":"5"},"devDependencies":{"@graphql-codegen/cli":"5"}}' > "$TGT/package.json"
echo '{}' > "$TGT/tsconfig.json"; touch "$TGT/codegen.ts"

# Simulates what /autodev:init would have written — there's no shell entry point for
# the actual command (it's prose, interpreted by Claude), so this test starts from
# its output instead of driving it.
mkdir -p "$TGT/.autodev"
jq '.client_name="SmokeCo" | .repo.local_path=$p | .tracker.kind="local"' \
  --arg p "$TGT" "$PLUGIN/reference/deployment.example.json" > "$TGT/.autodev/deployment.json"
bash "$PLUGIN/scripts/write-identity-pointer.sh" "$TGT" >/dev/null 2>&1

echo "footprint (the whole point of the plugin conversion):"
check "no .claude/skills written" bash -c "! test -d '$TGT/.claude/skills'"
check "no .claude/autodev.md written" bash -c "! test -f '$TGT/.claude/autodev.md'"
check "no scripts/autodev written" bash -c "! test -d '$TGT/scripts'"
check "team .claude/settings.json untouched" grep -q "Bash(ls" "$TGT/.claude/settings.json"
check "team AGENTS.md untouched" grep -q "Use the MUI theme" "$TGT/AGENTS.md"
check "team .claude/CLAUDE.md untouched" grep -q "team rules" "$TGT/.claude/CLAUDE.md"
check "pre-existing .git/hooks/pre-push untouched" grep -q "exit 0" "$TGT/.git/hooks/pre-push"
check "no {{ left unrendered in the plugin itself" bash -c \
  "! grep -rl '{{' '$PLUGIN/commands' '$PLUGIN/reference' '$PLUGIN/hooks' '$PLUGIN/scripts' 2>/dev/null"

echo "conventions:"
bash "$PLUGIN/scripts/detect-conventions.sh" "$TGT" > "$TGT/.autodev/conventions.md"
check "codegen rule detected" grep -q "GraphQL code generation" "$TGT/.autodev/conventions.md"
check "MUI theme rule detected" grep -q "Material UI" "$TGT/.autodev/conventions.md"
check "comment rule present" grep -q "explain WHY" "$TGT/.autodev/conventions.md"

echo "docs conflict scan:"
check "flags 'commit directly to main'" bash -c "bash '$PLUGIN/scripts/check-docs.sh' '$TGT' | grep -q 'only humans merge'"

echo "identity pointer (hook-less fallback):"
# scenario A: the main TGT has a TEAM CLAUDE.md — must have been preserved (asserted
# above). scenario B: bare repo -> pointer written. C: our stale pointer -> replaced.
T2=$(mktemp -d); git -C "$T2" init -q; echo '{}' > "$T2/package.json"
mkdir -p "$T2/.autodev"
jq '.client_name="BareCo" | .repo.local_path=$p | .tracker.kind="local"' \
  --arg p "$T2" "$PLUGIN/reference/deployment.example.json" > "$T2/.autodev/deployment.json"
bash "$PLUGIN/scripts/write-identity-pointer.sh" "$T2" >/dev/null 2>&1
check "bare repo gets the pointer" grep -q "autoDev POINTER" "$T2/.claude/CLAUDE.md"
check "pointer names the command surface" grep -q "/autodev:loop" "$T2/.claude/CLAUDE.md"
printf '# BareCo — autoDev engine\nold stale rulebook\n' > "$T2/.claude/CLAUDE.md"
bash "$PLUGIN/scripts/write-identity-pointer.sh" "$T2" >/dev/null 2>&1
check "our stale pointer is replaced (not treated as a team file)" grep -q "autoDev POINTER" "$T2/.claude/CLAUDE.md"
rm -rf "$T2"

echo "session engagement (session_mode: concierge | signal | silent):"
check "concierge (default): full identity + manual + conventions injected" bash -c \
  "echo '{\"cwd\":\"$TGT\"}' | CLAUDE_PLUGIN_ROOT='$PLUGIN' '$PLUGIN/hooks/session-signal.sh' | jq -e '.hookSpecificOutput.additionalContext | contains(\"You are\") and contains(\"concierge\") and contains(\"Non-negotiable\")'"
jq '.session_mode="signal"' "$TGT/.autodev/deployment.json" > "$TGT/.autodev/t" && mv "$TGT/.autodev/t" "$TGT/.autodev/deployment.json"
check "signal: one short line naming both commands" bash -c \
  "echo '{\"cwd\":\"$TGT\"}' | '$PLUGIN/hooks/session-signal.sh' | jq -e '.hookSpecificOutput.additionalContext | contains(\"/autodev:loop\") and contains(\"/autodev:new\") and (length < 200)'"
jq '.session_mode="silent"' "$TGT/.autodev/deployment.json" > "$TGT/.autodev/t" && mv "$TGT/.autodev/t" "$TGT/.autodev/deployment.json"
check "silent: nothing" bash -c \
  "test -z \"\$(echo '{\"cwd\":\"$TGT\"}' | '$PLUGIN/hooks/session-signal.sh')\""
jq 'del(.session_mode)' "$TGT/.autodev/deployment.json" > "$TGT/.autodev/t" && mv "$TGT/.autodev/t" "$TGT/.autodev/deployment.json"
UNCONF=$(mktemp -d)
check "silent when unconfigured" bash -c \
  "test -z \"\$(echo '{\"cwd\":\"$UNCONF\"}' | '$PLUGIN/hooks/session-signal.sh')\""
rmdir "$UNCONF"

echo "push guard (PreToolUse — replaces .git/hooks/pre-push):"
check "feature branch push allowed" bash -c \
  "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin feature/x\"},\"cwd\":\"$TGT\"}' | '$PLUGIN/hooks/guard-push.sh' | wc -c | tr -d '[:space:]' | grep -qx 0"
check "main branch push denied" bash -c \
  "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin main\"},\"cwd\":\"$TGT\"}' | '$PLUGIN/hooks/guard-push.sh' | jq -e '.hookSpecificOutput.permissionDecision == \"deny\"'"
jq '.review.delivery="local_diff"' "$TGT/.autodev/deployment.json" > "$TGT/.autodev/t" && mv "$TGT/.autodev/t" "$TGT/.autodev/deployment.json"
check "local_diff: even a feature push is denied" bash -c \
  "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin feature/x\"},\"cwd\":\"$TGT\"}' | '$PLUGIN/hooks/guard-push.sh' | jq -e '.hookSpecificOutput.permissionDecision == \"deny\"'"
jq '.review.delivery="draft_pr"' "$TGT/.autodev/deployment.json" > "$TGT/.autodev/t" && mv "$TGT/.autodev/t" "$TGT/.autodev/deployment.json"

echo "docs guard (PreToolUse — replaces the settings.json deny rule):"
check "Edit on AGENTS.md denied" bash -c \
  "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TGT/AGENTS.md\"}}' | '$PLUGIN/hooks/guard-docs.sh' | jq -e '.hookSpecificOutput.permissionDecision == \"deny\"'"
check "Edit elsewhere allowed" bash -c \
  "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TGT/src/foo.ts\"}}' | '$PLUGIN/hooks/guard-docs.sh' | wc -c | tr -d '[:space:]' | grep -qx 0"

echo "local tracker (git-native board):"
TRK="$PLUGIN/scripts/tracker.mjs"
LID=$(cd "$TGT" && node "$TRK" create-issue --title "Smoke story" --stage ready_for_ai_dev --labels ai-eligible 2>/dev/null)
check "create-issue returns an id" test -n "$LID"
check "move + note" bash -c "cd '$TGT' && node '$TRK' move '$LID' ai_development --note 'dev started' | grep -q 'AI Development'"
check "comment" bash -c "cd '$TGT' && node '$TRK' comment '$LID' 'progress'"
check "history recorded in issue file" bash -c "jq -e '.history | length >= 2' '$TGT/.autodev/board/$LID.json'"
check "board renders html" bash -c "cd '$TGT' && node '$TRK' board >/dev/null && test -f '$TGT/.autodev/board.html'"
check "tracker doctor ok" bash -c "cd '$TGT' && node '$TRK' doctor | grep -q 'local board'"

echo "vendored-install migration:"
T3=$(mktemp -d); git -C "$T3" init -q
mkdir -p "$T3/.claude/skills" "$T3/scripts/autodev" "$T3/.autodev/board" "$T3/.git/hooks"
echo "# X — autoDev engine manual" > "$T3/.claude/autodev.md"
echo "autoDev skill" > "$T3/.claude/skills/intake.md"
echo "team skill, unrelated" > "$T3/.claude/skills/myteam.md"
echo "old" > "$T3/scripts/autodev/linear.mjs"
echo '{"_comment":"autoDev headless permissions","permissions":{}}' > "$T3/.claude/settings.json"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$T3/.claude/settings.json.pre-autodev"
printf '#!/bin/sh\n# autoDev pre-push guard\nexit 1\n' > "$T3/.git/hooks/pre-push"
echo '{"client_name":"X","tracker":{"kind":"local"}}' > "$T3/.autodev/deployment.json"
echo '{"id":"AD-1"}' > "$T3/.autodev/board/AD-1.json"
bash "$PLUGIN/scripts/migrate-vendored.sh" "$T3" >/dev/null 2>&1
check "engine artifacts removed" bash -c "! test -f '$T3/.claude/autodev.md' && ! test -f '$T3/.claude/skills/intake.md' && ! test -d '$T3/scripts/autodev'"
check "team skill survives" test -f "$T3/.claude/skills/myteam.md"
check "team settings restored" grep -q "Bash(ls" "$T3/.claude/settings.json"
check "our pre-push removed" bash -c "! test -f '$T3/.git/hooks/pre-push'"
check "state preserved" bash -c "test -f '$T3/.autodev/deployment.json' && test -f '$T3/.autodev/board/AD-1.json'"
check "backup populated" test -f "$T3/.autodev/backup-vendored/.claude/autodev.md"
check "idempotent (2nd run finds nothing)" bash -c "bash '$PLUGIN/scripts/migrate-vendored.sh' '$T3' | grep -q 'no vendored install found'"
rm -rf "$T3"

echo "config schema upgrade + history detection:"
T5=$(mktemp -d); mkdir -p "$T5/.autodev" "$T5/scripts/autodev"; git -C "$T5" init -q
echo old > "$T5/scripts/autodev/linear.mjs"
jq 'del(.session_mode, .preview, .backup, .backlog, .intake.bugs, .tracker.instance_label, .qa.visual_qa)
    | .client_name="Hist Co" | .execution.max_lanes=2' "$PLUGIN/reference/deployment.example.json" > "$T5/.autodev/deployment.json"
check "session hook flags HISTORY (artifacts+schema) with the update steps" bash -c \
  "echo '{\"cwd\":\"$T5\"}' | CLAUDE_PLUGIN_ROOT='$PLUGIN' '$PLUGIN/hooks/session-signal.sh' | jq -e '.hookSpecificOutput.additionalContext | contains(\"HISTORY detected (artifacts+schema)\") and contains(\"upgrade-config.sh\") and contains(\"in flight\")'"
bash "$PLUGIN/scripts/upgrade-config.sh" "$T5" >/dev/null
check "upgrade adds new keys with defaults" bash -c "jq -e '.session_mode==\"concierge\" and .preview.enabled==true and (.intake.bugs==\"triage\") and (.backlog.enabled==false) and (.backlog.batch==3)' '$T5/.autodev/deployment.json'"
check "operator values preserved" bash -c "jq -e '.execution.max_lanes==2 and .client_name==\"Hist Co\"' '$T5/.autodev/deployment.json'"
check "instance label derived from client_name (not the example's)" bash -c "jq -e '.tracker.instance_label==\"autodev:hist-co\"' '$T5/.autodev/deployment.json'"
check "upgrade idempotent" bash -c "bash '$PLUGIN/scripts/upgrade-config.sh' '$T5' | grep -q 'already current'"
bash "$PLUGIN/scripts/migrate-vendored.sh" "$T5" >/dev/null 2>&1
check "after update: session hook no longer flags history" bash -c \
  "echo '{\"cwd\":\"$T5\"}' | CLAUDE_PLUGIN_ROOT='$PLUGIN' '$PLUGIN/hooks/session-signal.sh' | jq -e '.hookSpecificOutput.additionalContext | contains(\"HISTORY detected\") | not'"
rm -rf "$T5"

echo "autoQA surface (deep-dive QA + repro hunt):"
check "commands/qa.md exists" test -f "$PLUGIN/commands/qa.md"
check "commands/repro.md exists" test -f "$PLUGIN/commands/repro.md"
check "reference/deep-qa.md exists" test -f "$PLUGIN/reference/deep-qa.md"
check "reference/repro.md exists" test -f "$PLUGIN/reference/repro.md"
check "qa.md frontmatter has a description" bash -c \
  "sed -n '2,/^---\$/p' '$PLUGIN/commands/qa.md' | grep -q '^description: .'"
check "repro.md frontmatter has a description" bash -c \
  "sed -n '2,/^---\$/p' '$PLUGIN/commands/repro.md' | grep -q '^description: .'"
check "example config declares deep_dive.final_review" bash -c \
  "jq -e '.qa.deep_dive.final_review' '$PLUGIN/reference/deployment.example.json'"
check "example config declares the repro caps" bash -c \
  "jq -e '.qa.repro.max_attempts and .qa.repro.wall_clock_minutes' '$PLUGIN/reference/deployment.example.json'"
# a config that predates the autoQA keys must gain them on upgrade, operator values intact
T6=$(mktemp -d); mkdir -p "$T6/.autodev"
jq 'del(.qa.deep_dive, .qa.repro) | .commands.test="npm run custom-test"' \
  "$PLUGIN/reference/deployment.example.json" > "$T6/.autodev/deployment.json"
bash "$PLUGIN/scripts/upgrade-config.sh" "$T6" >/dev/null
check "upgrade adds autoQA keys with defaults" bash -c \
  "jq -e '.qa.deep_dive.final_review==true and .qa.repro.max_attempts==7 and .qa.repro.wall_clock_minutes==45' '$T6/.autodev/deployment.json'"
check "operator commands.test survives the merge" bash -c \
  "jq -e '.commands.test==\"npm run custom-test\"' '$T6/.autodev/deployment.json'"
rm -rf "$T6"

echo "shortcut tracker (driver + schema, no network):"
check "shortcut.mjs parses" node --check "$PLUGIN/scripts/shortcut.mjs"
check "tracker.mjs parses" node --check "$PLUGIN/scripts/tracker.mjs"
check "tracker.mjs dispatches kind=shortcut" bash -c \
  "grep -q \"KIND === 'shortcut'\" '$PLUGIN/scripts/tracker.mjs' && grep -q 'shortcut.mjs' '$PLUGIN/scripts/tracker.mjs'"
check "example config has the shortcut block" bash -c \
  "jq -e '.tracker.shortcut.api_token_env==\"SHORTCUT_API_TOKEN\" and .tracker.shortcut.workflow_id and .tracker.shortcut.statuses' '$PLUGIN/reference/deployment.example.json'"
# the engine's stage vocabulary must be identical across API trackers
check "stage-key parity: shortcut statuses == linear statuses" bash -c \
  "jq -e '(.tracker.statuses | keys) == (.tracker.shortcut.statuses | keys)' '$PLUGIN/reference/deployment.example.json'"
check "ops/shortcut-setup.md exists" test -f "$PLUGIN/ops/shortcut-setup.md"

echo "persona resolution (ensure-personas.sh — no network in any of these):"
check "ensure-personas.sh parses" bash -n "$PLUGIN/scripts/ensure-personas.sh"
check "example config declares auto_install / fallback / pinned library" bash -c \
  "jq -e '.personas.auto_install==true and .personas.fallback==\"general-purpose\" and (.personas.library.ref|length>10)' '$PLUGIN/reference/deployment.example.json'"
T7=$(mktemp -d); mkdir -p "$T7/.autodev" "$T7/agents"
# needed set: bare-file resolve, prefixed-file resolve, builtin, and two genuinely missing
jq '.personas.roster=["backend-architect","code-reviewer"]
    | .personas.stage_defaults={}
    | .personas.dev_routing=[{"match":"x","persona":"frontend-developer"}]
    | .personas.qa_angles={"verdict":"reality-checker"}' \
  "$PLUGIN/reference/deployment.example.json" > "$T7/.autodev/deployment.json"
touch "$T7/agents/backend-architect.md" "$T7/agents/engineering-code-reviewer.md"
POUT=$(AUTODEV_AGENTS_DIR="$T7/agents" bash "$PLUGIN/scripts/ensure-personas.sh" --check "$T7")
# match on the text, not the ✓ glyph — ANSI reset codes sit between them
check "bare filename resolves" bash -c "echo '$POUT' | grep -q ' backend-architect\$'"
check "prefixed library filename resolves (fuzzy)" bash -c "echo '$POUT' | grep -q ' code-reviewer\$'"
check "fallback persona counts as built-in" bash -c "echo '$POUT' | grep -q 'general-purpose (built-in)'"
check "missing personas report UNRESOLVED with the fallback" bash -c \
  "echo '$POUT' | grep 'reality-checker UNRESOLVED' | grep -q 'general-purpose'"
check "summary line totals the sets" bash -c "echo '$POUT' | grep -q '5 needed · 3 installed · 0 downloaded · 2 unresolved'"
check "--check downloads nothing" bash -c "test \$(ls '$T7/agents' | wc -l) -eq 2"
jq '.personas.auto_install=false' "$T7/.autodev/deployment.json" > "$T7/t" && mv "$T7/t" "$T7/.autodev/deployment.json"
check "auto_install=false full run: no download side effects, still reports" bash -c \
  "AUTODEV_AGENTS_DIR='$T7/agents' bash '$PLUGIN/scripts/ensure-personas.sh' '$T7' | grep -q '2 unresolved' && test \$(ls '$T7/agents' | wc -l) -eq 2"
# consent fails CLOSED: a mistyped string "false" must behave like false, never re-enable downloads
jq '.personas.auto_install="false"' "$T7/.autodev/deployment.json" > "$T7/t" && mv "$T7/t" "$T7/.autodev/deployment.json"
check "non-boolean auto_install fails closed (no download attempt)" bash -c \
  "AUTODEV_AGENTS_DIR='$T7/agents' bash '$PLUGIN/scripts/ensure-personas.sh' '$T7' 2>/dev/null | grep -q '2 unresolved' && test \$(ls '$T7/agents' | wc -l) -eq 2"
# a config predating the persona keys gains them on upgrade
jq 'del(.personas.auto_install, .personas.fallback, .personas.library)' \
  "$PLUGIN/reference/deployment.example.json" > "$T7/.autodev/deployment.json"
bash "$PLUGIN/scripts/upgrade-config.sh" "$T7" >/dev/null
check "upgrade adds persona-resolution keys" bash -c \
  "jq -e '.personas.auto_install==true and .personas.fallback==\"general-purpose\" and .personas.library.repo==\"msitarzewski/agency-agents\"' '$T7/.autodev/deployment.json'"
rm -rf "$T7"

echo "vendored install mode (install.sh — the plugin's sibling):"
T4=$(mktemp -d); git -C "$T4" init -q; mkdir -p "$T4/.autodev" "$T4/.claude"
echo '{"permissions":{"allow":["Bash(ls:*)"]},"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo team-hook"}]}]}}' > "$T4/.claude/settings.json"
jq '.client_name="VendCo" | .tracker.kind="local"' "$PLUGIN/reference/deployment.example.json" > "$T4/.autodev/deployment.json"
check "installs cleanly" bash "$PLUGIN/install.sh" "$T4"
check "engine copied + paths rewritten (no plugin-root refs in commands)" bash -c "! grep -rl 'CLAUDE_PLUGIN_ROOT' '$T4/.claude/commands'"
check "namespace rewritten (/autodev-*)" bash -c "! grep -rq '/autodev:' '$T4/.claude/commands'"
check "team settings merged, not clobbered" bash -c "jq -e '.permissions.allow[0]==\"Bash(ls:*)\" and ([.hooks.SessionStart[].hooks[].command] | any(contains(\"team-hook\")))' '$T4/.claude/settings.json'"
check "vendored concierge hook runs standalone" bash -c "echo '{\"cwd\":\"$T4\"}' | '$T4/.autodev/engine/hooks/session-signal.sh' | jq -e '.hookSpecificOutput.additionalContext | contains(\"You are\")'"
check "vendored push guard denies main" bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin main\"},\"cwd\":\"$T4\"}' | '$T4/.autodev/engine/hooks/guard-push.sh' | jq -e '.hookSpecificOutput.permissionDecision==\"deny\"'"
check "engine stamped vendored + versioned" bash -c "jq -e '.engine.mode==\"vendored\" and .engine.version' '$T4/.autodev/deployment.json'"
bash "$PLUGIN/install.sh" "$T4" >/dev/null 2>&1
check "re-install idempotent (our hook once)" bash -c "jq -e '[.hooks.SessionStart[].hooks[].command | select(contains(\".autodev/engine\"))] | length == 1' '$T4/.claude/settings.json'"
jq '.enabledPlugins={"autodev@x":true}' "$T4/.claude/settings.json" > "$T4/t" && mv "$T4/t" "$T4/.claude/settings.json"
check "refuses when plugin enabled (one mode per repo)" bash -c "! bash '$PLUGIN/install.sh' '$T4'"
jq 'del(.enabledPlugins)' "$T4/.claude/settings.json" > "$T4/t" && mv "$T4/t" "$T4/.claude/settings.json"
bash "$PLUGIN/scripts/migrate-vendored.sh" "$T4" >/dev/null 2>&1
check "migrate cleans NEW vendored layout too (engine dir + commands + hooks)" bash -c \
  "! test -d '$T4/.autodev/engine' && ! test -f '$T4/.claude/commands/autodev-loop.md' && jq -e '[.hooks[]?[]?.hooks[]?.command // empty] | all(contains(\".autodev/engine\") | not)' '$T4/.claude/settings.json' && jq -e '[.hooks.SessionStart[].hooks[].command] | any(contains(\"team-hook\"))' '$T4/.claude/settings.json'"
rm -rf "$T4"

echo
if [[ $FAIL -eq 0 ]]; then echo "smoke: PASS"; else echo "smoke: FAIL"; fi
exit $FAIL

#!/usr/bin/env bash
# autoDev — one heartbeat tick. Fired by the timer (interval = execution.tick_interval_minutes
# in the target repo's .autodev/deployment.json). Stateless: all real state lives on the
# board + git. Safe to run anytime.
#
# Lives at a stable per-operator path (~/.autodev/bin/ by convention — see
# ops/launchd-timer.md), copied there alongside its sibling scripts (notify.sh,
# watchdog.sh, tracker.mjs, linear.mjs, report.mjs) so a launchd plist path survives
# a plugin update (the plugin's own cache directory is versioned and moves).
#
# Usage: devloop-tick.sh <repo-path>
set -uo pipefail

REPO="${1:?usage: devloop-tick.sh <repo-path>}"
CONFIG="$REPO/.autodev/deployment.json"
[[ -f "$CONFIG" ]] || { echo "devloop-tick: no $CONFIG" >&2; exit 1; }

RUN_HOME="$(jq -r '.runner.home_dir // "~/.autodev"' "$CONFIG")"
RUN_HOME="${RUN_HOME/#\~/$HOME}"
mkdir -p "$RUN_HOME/logs"

# Single-flight lock — portable (macOS has no flock). A stale lock from a killed
# tick self-clears: if the recorded PID is no longer alive, we take the lock.
LOCK="$RUN_HOME/devloop.lock"
if [[ -f "$LOCK" ]] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  exit 0                             # previous tick still running — skip, don't stack
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
touch "$RUN_HOME/heartbeat"          # prove the runner is alive (even while paused)

# --- rate-limit gate: if a reset time is recorded and still ahead, no-op ---
PAUSE="$RUN_HOME/rate-limited-until"
if [[ -f "$PAUSE" ]]; then
  now=$(date +%s); until=$(cat "$PAUSE" 2>/dev/null || echo 0)
  if [[ "$now" -lt "$until" ]]; then exit 0; fi
  rm -f "$PAUSE"; "$(dirname "$0")/notify.sh" "$REPO" resumed
fi

# --- build the headless allowlist from THIS repo's config; never written to disk ---
ALLOW=()
add() { ALLOW+=(--allowedTools "$1"); }
for c in install test lint build app_run; do
  v=$(jq -r --arg c "$c" '.commands[$c] // empty' "$CONFIG")
  [[ -n "$v" ]] && add "Bash($v)"
done
DEFAULT_BRANCH=$(jq -r '.repo.default_branch // "main"' "$CONFIG")
FEATURE_PREFIX=$(jq -r '.repo.feature_branch_prefix // "feature/"' "$CONFIG")
STORY_PREFIX=$(jq -r '.repo.story_branch_prefix // "autodev"' "$CONFIG")
BACKUP_REMOTE=$(jq -r '.backup.remote // "origin"' "$CONFIG")
add "Bash(git status:*)"; add "Bash(git add:*)"; add "Bash(git commit:*)"
add "Bash(git checkout:*)"; add "Bash(git switch:*)"; add "Bash(git branch:*)"
add "Bash(git worktree:*)"; add "Bash(git diff:*)"; add "Bash(git log:*)"
add "Bash(git rebase:*)"; add "Bash(git merge --squash:*)"
add "Bash(git push origin ${FEATURE_PREFIX}*)"
add "Bash(git push origin ${STORY_PREFIX}/*)"
add "Bash(git push ${BACKUP_REMOTE} ${FEATURE_PREFIX}*)"
add "Bash(gh pr create:*)"; add "Bash(gh pr view:*)"; add "Bash(gh pr comment:*)"
add "Bash(gh pr checks:*)"; add "Bash(gh pr merge:*)"
add "Bash(node *)"; add "Bash(jq *)"
add "mcp__linear__*"; add "mcp__playwright__*"

cd "$REPO" || exit 1
OUT=$(claude -p "/autodev:loop" --output-format json "${ALLOW[@]}" 2>>"$RUN_HOME/logs/err.log")
echo "$OUT" >> "$RUN_HOME/logs/$(date +%F).jsonl"

# --- detect a usage-limit result and record the reset time ---
# NOTE: confirm the exact field against the installed Claude Code version.
if echo "$OUT" | jq -e '.is_error and (.result // "" | ascii_downcase
      | test("usage limit|rate limit"))' >/dev/null 2>&1; then
  reset=$(echo "$OUT" | jq -r '.reset_at_epoch // empty' 2>/dev/null)
  [[ -z "$reset" ]] && reset=$(( $(date +%s) + 3600 ))   # fallback: back off 1h
  echo "$reset" > "$PAUSE"
  "$(dirname "$0")/notify.sh" "$REPO" limited "$reset"
fi

# --- operator digest (B4): cheap, self-gates on reporting.cadence; no-op if off/not-due ---
AUTODEV_CONFIG="$CONFIG" node "$(dirname "$0")/report.mjs" >/dev/null 2>>"$RUN_HOME/logs/err.log" || true

# --- Linear mirror flush: async, off the critical path; self-gates (no-op unless
# tracker.kind=local + tracker.mirror.linear). Failures defer to the next tick. ---
AUTODEV_CONFIG="$CONFIG" node "$(dirname "$0")/tracker.mjs" flush-mirror >/dev/null 2>>"$RUN_HOME/logs/err.log" || true

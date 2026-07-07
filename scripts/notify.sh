#!/usr/bin/env bash
# autoDev — surface engine state to the board via tracker.mjs (retry/backoff built in).
#
# Usage:
#   notify.sh <repo-path> limited <reset_epoch>   # engine hit a usage limit, auto-resuming
#   notify.sh <repo-path> resumed                 # engine resumed after a rate-limit pause
#   notify.sh <repo-path> stalled  <age_seconds>  # watchdog: heartbeat went stale
#
# Token (kept OFF chat / out of git): $LINEAR_API_TOKEN or
#   ~/.config/autodev/<client>.linear.token  (tracker.mjs resolves it)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${1:?usage: notify.sh <repo-path> {limited <epoch>|resumed|stalled <age>}}"
export AUTODEV_CONFIG="$REPO/.autodev/deployment.json"
KIND="${2:-}"
RUN_HOME="$(jq -r '.runner.home_dir // "~/.autodev"' "$AUTODEV_CONFIG" 2>/dev/null || echo "~/.autodev")"
RUN_HOME="${RUN_HOME/#\~/$HOME}"
LOG="$RUN_HOME/logs/notify.log"
mkdir -p "$(dirname "$LOG")"

ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "$(ts) [$KIND] $*" >> "$LOG"; }

case "$KIND" in
  limited)
    when=$(date -r "${3:-0}" "+%H:%M" 2>/dev/null || echo "soon")
    TITLE="⏳ autoDev rate-limited — auto-resuming at ${when}. No action needed." ;;
  resumed)
    TITLE="▶️ autoDev resumed after a rate-limit pause." ;;
  stalled)
    mins=$(( ${3:-0} / 60 ))
    TITLE="⚠️ ENGINE STALLED — no heartbeat for ~${mins} min. Check the runner host." ;;
  *) echo "usage: notify.sh <repo-path> {limited <epoch>|resumed|stalled <age>}" >&2; exit 1 ;;
esac

log "$TITLE"
node "$HERE/tracker.mjs" create-issue --title "$TITLE" >> "$LOG" 2>&1 || log "board post failed (logged locally only)"

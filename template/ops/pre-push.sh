#!/usr/bin/env bash
# autoDev pre-push guard — installed to .git/hooks/pre-push by install.sh.
#
# Enforces the Delivery mode against the ENGINE only: pushes from inside a Claude Code
# session (CLAUDECODE env set) are constrained; a human pushing from their own terminal
# is never blocked. Reads .autodev/deployment.json at runtime, so config changes apply
# without reinstalling. Fails open if autoDev isn't active in this clone.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
CONFIG="$ROOT/.autodev/deployment.json"
STDIN_REFS="$(cat)"

# Chain a pre-existing team hook first (backed up by install.sh) — their rules still apply.
if [ -x "$ROOT/.git/hooks/pre-push.pre-autodev" ]; then
  printf '%s' "$STDIN_REFS" | "$ROOT/.git/hooks/pre-push.pre-autodev" "$@" || exit 1
fi

[ -f "$CONFIG" ] || exit 0                      # autoDev not installed here
command -v jq >/dev/null 2>&1 || exit 0         # can't read config — don't break pushes
[ -n "${CLAUDECODE:-}" ] || exit 0              # human terminal — never block

DELIVERY=$(jq -r '.review.delivery // "draft_pr"' "$CONFIG")
DEFAULT_BRANCH=$(jq -r '.repo.default_branch // "main"' "$CONFIG")

if [ "$DELIVERY" = "local_diff" ]; then
  echo "autoDev pre-push: BLOCKED — review.delivery=local_diff (LOCAL-ONLY mode)." >&2
  echo "The engine never pushes in this mode; present a local diff instead (autodev.md ▸ Delivery mode)." >&2
  exit 1
fi

# draft_pr: engine may push feature/story/backup branches, never the default branch.
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  [ -z "${remote_ref:-}" ] && continue
  if [ "$remote_ref" = "refs/heads/$DEFAULT_BRANCH" ]; then
    echo "autoDev pre-push: BLOCKED — only humans merge '$DEFAULT_BRANCH' (Gate 2 + branch protection)." >&2
    exit 1
  fi
done <<< "$STDIN_REFS"

exit 0

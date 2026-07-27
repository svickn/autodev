#!/usr/bin/env bash
# autoDev — upgrade an existing .autodev/deployment.json to the current schema.
# Adds keys the config predates (session_mode, intake.bugs, preview, backup,
# tracker.instance_label/mirror, qa.visual_qa/test_layers, …) with their defaults;
# NEVER changes a value the operator already set (existing values always win).
# The example's "_note" documentation keys are stripped so client configs stay lean.
# Also splits legacy-inline local-only fields (repo.local_path, runner.*) out into
# .autodev/deployment.local.json (gitignored) the first time it runs on an unsplit
# config — never touches a local file that already exists.
# Idempotent; prints exactly what it added/split. Usage: upgrade-config.sh [repo]
set -uo pipefail

REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
CFG="$REPO/.autodev/deployment.json"
LOCAL="$REPO/.autodev/deployment.local.json"
EXAMPLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/reference/deployment.example.json"
[[ -f "$CFG" ]] || { echo "no $CFG — nothing to upgrade (run /autodev:init to configure)"; exit 0; }
jq empty "$CFG" 2>/dev/null || { echo "✗ $CFG is not valid JSON — fix it first" >&2; exit 1; }

# --- split: move legacy-inline local-only fields out to deployment.local.json ---
if [[ ! -f "$LOCAL" ]]; then
  LOCAL_CONTENT=$(jq '
    def paths_list: [["repo","local_path"],["runner","home_dir"],["runner","heartbeat_file"],["runner","rate_limited_file"],["runner","logs_dir"]];
    . as $cfg
    | reduce paths_list[] as $p
        ({}; ($cfg | getpath($p)) as $v | if $v != null then setpath($p; $v) else . end)
  ' "$CFG")
  if [[ "$(jq -c . <<<"$LOCAL_CONTENT")" != "{}" ]]; then
    echo "$LOCAL_CONTENT" > "$LOCAL"
    jq 'del(.repo.local_path, .runner)' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
    echo "✓ split legacy local fields into $LOCAL:"
    jq -r '[paths(scalars)] | map(join(".")) | .[] | "    + " + .' <<<"$LOCAL_CONTENT"
  fi
fi

BEFORE=$(jq -c '[paths(scalars)]' "$CFG")
# defaults (notes stripped, identity/example-only fields dropped) deep-merged UNDER
# the existing config — jq's * is right-biased, so operator values always win
jq -s '
  (.[0]
    | walk(if type=="object" then with_entries(select(.key|startswith("_")|not)) else . end)
    | del(.client_name, .assistant_name, .repo, .bot_identity, .tracker.team, .tracker.team_key, .tracker.team_id, .braingrid.project_short_id, .commands, .engine)
  ) * .[1]
' "$EXAMPLE" "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"

# the example's literal instance label must not leak — derive it from client_name
if [[ "$(jq -r '.tracker.instance_label // ""' "$CFG")" == "autodev:acmeco" ]]; then
  jq '.tracker.instance_label = ("autodev:" + (.client_name // "client" | ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "")))' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
fi

ADDED=$(jq -n --argjson a "$BEFORE" --argjson b "$(jq -c '[paths(scalars)]' "$CFG")" \
  '($b - $a) | map(join(".")) | sort')
N=$(echo "$ADDED" | jq 'length')
if [[ "$N" -eq 0 ]]; then
  echo "✓ config already current — nothing added"
else
  echo "✓ config upgraded — $N key(s) added with defaults (your existing values untouched):"
  echo "$ADDED" | jq -r '.[] | "    + " + .'
  echo "  review the additions: git diff .autodev/deployment.json"
fi

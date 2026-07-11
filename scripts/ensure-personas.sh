#!/usr/bin/env bash
# autoDev — persona resolution + on-demand install (agency-agents).
# Personas are subagent .md files in the agents dir ($AUTODEV_AGENTS_DIR, default
# ~/.claude/agents). This computes the set THIS deployment needs (personas.roster +
# stage_defaults + dev_routing + qa_angles + fallback), resolves each against the
# agents dir — bare <slug>.md or the library's division-prefixed *-<slug>.md — and,
# unless --check or personas.auto_install=false, downloads ONLY the missing ones from
# the pinned personas.library ref (MIT; attribution in README ▸ Agent roster). Fetch
# failures are soft: the persona reports UNRESOLVED and the engine spawns
# personas.fallback instead (reference/manual.md ▸ Commands). --check never touches
# the network. Exit non-zero only on a hard error (missing config / jq).
# Usage: ensure-personas.sh [--check] [repo]
set -uo pipefail

CHECK=0
[[ "${1:-}" == "--check" ]] && { CHECK=1; shift; }
REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
CFG="$REPO/.autodev/deployment.json"
[[ -f "$CFG" ]] || { echo "ensure-personas: no $CFG (run /autodev:init first)" >&2; exit 1; }
command -v jq >/dev/null || { echo "ensure-personas: jq missing" >&2; exit 1; }

AGENTS_DIR="${AUTODEV_AGENTS_DIR:-$HOME/.claude/agents}"
# NOT `// true` — jq's // treats an explicit false as absent and would re-enable downloads
AUTO=$(jq -r 'if (.personas.auto_install|type)=="boolean" then .personas.auto_install else true end' "$CFG")
FALLBACK=$(jq -r '.personas.fallback // "general-purpose"' "$CFG")
LIB_REPO=$(jq -r '.personas.library.repo // "msitarzewski/agency-agents"' "$CFG")
LIB_REF=$(jq -r '.personas.library.ref // "main"' "$CFG")

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
got()  { printf '  \033[32m⬇\033[0m %s\n' "$1"; }
miss() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

# every slug the config can route to, "_note" documentation keys excluded
NEEDED=$(jq -r '
  ([.personas.roster[]?]
   + [.personas.stage_defaults // {} | with_entries(select(.key|startswith("_")|not)) | .[]]
   + [.personas.dev_routing[]?.persona]
   + [.personas.qa_angles // {} | with_entries(select(.key|startswith("_")|not)) | .[]
      | if type=="array" then .[] else . end]
   + [.personas.fallback // "general-purpose"])
  | map(select(type=="string" and . != "")) | unique | .[]' "$CFG")
[[ -n "$NEEDED" ]] || { echo "ensure-personas: nothing to resolve (empty personas config)"; exit 0; }

resolved() { # bare filename, or the library's division-prefixed one
  [[ -f "$AGENTS_DIR/$1.md" ]] && return 0
  compgen -G "$AGENTS_DIR/*-$1.md" >/dev/null 2>&1
}

TREE=""   # one tree fetch per run, only when the first download needs it
tree() {
  [[ -n "$TREE" ]] && return 0
  TREE=$(curl -fsS --max-time 20 "https://api.github.com/repos/$LIB_REPO/git/trees/$LIB_REF?recursive=1" \
         | jq -r '.tree[]?.path' 2>/dev/null) || TREE=""
  [[ -n "$TREE" ]]
}

n_inst=0 n_dl=0 n_un=0
UNRES=""
while IFS= read -r slug; do
  if [[ "$slug" == "general-purpose" ]]; then ok "$slug (built-in)"; n_inst=$((n_inst+1)); continue; fi
  if resolved "$slug"; then ok "$slug"; n_inst=$((n_inst+1)); continue; fi
  if [[ $CHECK -eq 1 || "$AUTO" != "true" ]]; then
    miss "$slug UNRESOLVED — engine will run it as $FALLBACK"
    n_un=$((n_un+1)); UNRES+="$slug "; continue
  fi
  path=""
  tree && path=$(printf '%s\n' "$TREE" | grep -E -m1 "(^|/)([a-z0-9-]+-)?$slug\.md$" || true)
  if [[ -n "$path" ]]; then
    mkdir -p "$AGENTS_DIR"
    dest="$AGENTS_DIR/$(basename "$path")"
    if curl -fsS --max-time 30 "https://raw.githubusercontent.com/$LIB_REPO/$LIB_REF/$path" -o "$dest" && [[ -s "$dest" ]]; then
      got "$slug downloaded ($(basename "$path") @ ${LIB_REF:0:9})"; n_dl=$((n_dl+1)); continue
    fi
    rm -f "$dest"
  fi
  miss "$slug UNRESOLVED (not in library / fetch failed) — engine will run it as $FALLBACK"
  n_un=$((n_un+1)); UNRES+="$slug "
done <<< "$NEEDED"

# suffix built outside the expansion — bash 3.2 (macOS) mangles multibyte chars in ${:+}
SFX=""
[[ -n "$UNRES" ]] && SFX=" (${UNRES%% }-> $FALLBACK)"
echo "personas: $((n_inst+n_dl+n_un)) needed · $n_inst installed · $n_dl downloaded · $n_un unresolved$SFX"
exit 0

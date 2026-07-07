# autoDev → Claude Code Plugin Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert this repo from an `install.sh` template-renderer into a real Claude Code plugin — nothing is copied into a client repo, and autoDev never acts until `/autodev:init`, `/autodev:new`, or `/autodev:loop` is explicitly invoked.

**Architecture:** The engine repo becomes the plugin package itself (`.claude-plugin/plugin.json`, `commands/`, `reference/`, `scripts/`, `hooks/`, `ops/`). Three commands are the only discoverable surface. Per-repo state shrinks to `.autodev/deployment.json` + lazily-created runtime files — nothing under `.claude/` is ever written. A `PreToolUse` hook replaces the `.git/hooks/pre-push` guard; a one-line `SessionStart` hook replaces the full-manual injection.

**Tech Stack:** Bash (commands' scripts, hooks), Node.js ESM (`tracker.mjs`, `linear.mjs`, `report.mjs` — already dependency-free, using only `node:fs`/`node:path`/`node:child_process`/`fetch`), `jq` for JSON in shell, Markdown (commands/reference docs read by Claude at runtime).

**Reference spec:** `docs/superpowers/specs/2026-07-07-plugin-conversion-design.md`

## Global Constraints

- Nothing under a client repo's `.claude/` directory is ever written by any plugin script, command, or hook.
- No skill/command auto-fires from plain conversation — the only discoverable entry points are `/autodev:init`, `/autodev:new`, `/autodev:loop`.
- Every `{{PLACEHOLDER}}` token from the old template system is gone from the shipped plugin — verified by `grep -rl '{{' commands/ reference/ hooks/ scripts/` returning nothing (the one intentional exception, `ops/launchd.plist.template`, stays templated by design — it's rendered by hand only when an operator opts into the 24/7 timer).
- All path references inside reference/command docs to the engine's own scripts use `${CLAUDE_PLUGIN_ROOT}/scripts/...`, never a bare `scripts/autodev/...` (that path no longer exists in a client repo).
- `tracker.mjs`, `linear.mjs`, `report.mjs`, `check-docs.sh` already resolve `.autodev/deployment.json` dynamically (via `$AUTODEV_CONFIG` or by walking up from `cwd`) — per their own header comments, they were already written to be relocatable. These get moved verbatim, not rewritten.
- One refinement beyond the literal spec text: the spec's "copy just the 3 timer scripts to `~/.autodev/bin/`" is widened to "copy the whole `scripts/` directory" — `devloop-tick.sh`/`watchdog.sh`/`notify.sh` call `tracker.mjs`/`linear.mjs`/`report.mjs` via `$(dirname "$0")`, so all six must live together at that stable path or the cross-calls break after a plugin update moves the versioned cache dir. This is called out explicitly in Task 17/18/19 — flagging it here since it's an implementation-level correction of the spec, not a silent deviation.
- One addition beyond the literal spec text: the spec's Push Guard section only covers `git push`, but `reference/manual.md` non-negotiable 11 depends on a settings.json `deny` rule that no longer exists once `settings.json` is removed. Task 16 adds a second `PreToolUse` hook (`guard-docs.sh`) blocking Edit/Write on `AGENTS.md`/`CLAUDE.md`, using the exact same mechanism as the push guard, to preserve that guarantee. Flagged here for the same reason.

---

### Task 1: Plugin scaffold — manifest + directory skeleton

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create (empty, via `.gitkeep` or first real file in a later task): `commands/`, `reference/`, `scripts/`, `hooks/`, `ops/`
- Delete: `VERSION` (superseded by `plugin.json`'s `version` field)

**Interfaces:**
- Produces: `.claude-plugin/plugin.json` with `name: "autodev"` — every command in later tasks is invoked as `/autodev:<command-file-basename>`.

- [ ] **Step 1: Create the plugin manifest**

```bash
mkdir -p /Users/svickn/working/autodev/.claude-plugin
```

```json
{
  "name": "autodev",
  "description": "Autonomous PM→dev→QA engine driven by Claude Code — turns approved PRDs into QA'd, human-reviewable, shipped code through a board (a local git-native board or Linear), with two human gates. Nothing runs until you invoke /autodev:init, /autodev:new, or /autodev:loop.",
  "version": "2.0.0",
  "author": { "name": "Stacy Vicknair" },
  "license": "Apache-2.0",
  "homepage": "https://github.com/svickn/autodev",
  "repository": "https://github.com/svickn/autodev",
  "keywords": ["autonomous", "pm", "qa", "linear", "devloop", "agent"]
}
```

Write this to `.claude-plugin/plugin.json`.

- [ ] **Step 2: Create the directory skeleton**

```bash
mkdir -p /Users/svickn/working/autodev/commands /Users/svickn/working/autodev/reference \
         /Users/svickn/working/autodev/scripts /Users/svickn/working/autodev/hooks \
         /Users/svickn/working/autodev/ops
```

- [ ] **Step 3: Remove the superseded VERSION file**

```bash
git -C /Users/svickn/working/autodev rm VERSION
```

- [ ] **Step 4: Verify the manifest is valid JSON**

Run: `jq . /Users/svickn/working/autodev/.claude-plugin/plugin.json`
Expected: pretty-printed JSON, no error.

- [ ] **Step 5: Commit**

```bash
cd /Users/svickn/working/autodev
git add .claude-plugin/plugin.json
git commit -m "feat(plugin): add plugin manifest, remove standalone VERSION file"
```

---

### Task 2: Port the already-portable scripts unchanged

These four already resolve `.autodev/deployment.json` at runtime by walking up from `cwd` (or `$AUTODEV_CONFIG`) — per their own header comments they were written client-agnostic. They need zero content changes, only relocation.

**Files:**
- Move: `template/scripts/tracker.mjs` → `scripts/tracker.mjs`
- Move: `template/scripts/linear.mjs` → `scripts/linear.mjs`
- Move: `template/scripts/report.mjs` → `scripts/report.mjs`
- Move: `template/scripts/check-docs.sh` → `scripts/check-docs.sh`

**Interfaces:**
- Produces: `scripts/tracker.mjs` (CLI: `move|comment|show|create-issue|update-issue|relate|attach|create-project|create-milestone|state-id|whoami|doctor|list|board|flush-mirror`), `scripts/linear.mjs` (same surface minus `list`/`board`/`flush-mirror`, plus `set-project-status`/`create-project-status`), `scripts/report.mjs` (no args besides optional `--force`), `scripts/check-docs.sh <repo_path>`.
- Consumes: nothing from earlier tasks except that `scripts/` exists (Task 1).

- [ ] **Step 1: Move the four files**

```bash
cd /Users/svickn/working/autodev
git mv template/scripts/tracker.mjs scripts/tracker.mjs
git mv template/scripts/linear.mjs scripts/linear.mjs
git mv template/scripts/report.mjs scripts/report.mjs
git mv template/scripts/check-docs.sh scripts/check-docs.sh
chmod +x scripts/check-docs.sh
```

- [ ] **Step 2: Verify no `{{` placeholders slipped in (there shouldn't be any — sanity check)**

Run: `grep -n '{{' scripts/tracker.mjs scripts/linear.mjs scripts/report.mjs scripts/check-docs.sh`
Expected: no output (exit 1, no matches).

- [ ] **Step 3: Smoke-test `tracker.mjs` against a scratch repo (local board mode)**

```bash
TGT=$(mktemp -d) && git -C "$TGT" init -q
mkdir -p "$TGT/.autodev"
jq '.client_name="ScratchCo" | .tracker.kind="local"' \
  /Users/svickn/working/autodev/config/deployment.example.json > "$TGT/.autodev/deployment.json"
cd "$TGT" && node /Users/svickn/working/autodev/scripts/tracker.mjs create-issue --title "test" --stage ready_for_ai_dev
```

Expected: prints an id like `AD-1`, and `$TGT/.autodev/board/AD-1.json` exists.

```bash
rm -rf "$TGT"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/svickn/working/autodev
git add scripts/tracker.mjs scripts/linear.mjs scripts/report.mjs scripts/check-docs.sh
git commit -m "feat(plugin): relocate config-agnostic scripts into the plugin package"
```

---

### Task 3: Port `detect-conventions.sh` (one placeholder fix)

**Files:**
- Move: `template/scripts/detect-conventions.sh` → `scripts/detect-conventions.sh`

**Interfaces:**
- Produces: `scripts/detect-conventions.sh <repo_path>` — prints a markdown report to stdout (unchanged CLI contract from before).

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/scripts/detect-conventions.sh scripts/detect-conventions.sh
chmod +x scripts/detect-conventions.sh
```

- [ ] **Step 2: Fix the one `{{CMD_LINT}}` placeholder**

The file has no config access (it only takes a repo path), so replace the baked-in command reference with generic phrasing instead of wiring in JSON parsing.

```
Old string:
[ -n "$FMT" ] && echo "- **Formatting/style is enforced by: ${FMT}** — match it (run the formatter / \`{{CMD_LINT}}\`); don't hand-style or fight the config."

New string:
[ -n "$FMT" ] && echo "- **Formatting/style is enforced by: ${FMT}** — match it (run the formatter / your \`commands.lint\`); don't hand-style or fight the config."
```

- [ ] **Step 3: Also fix the stale comment referencing the old install/SessionStart pipeline**

```
Old string:
# autoDev — convention auto-detector. Scans the TARGET repo for the house patterns
# a fresh-context dev agent would otherwise reinvent (generated types, design
# system/theme, data layer, testing) and emits a prescriptive markdown report.
# install.sh runs this and writes the result to .autodev/conventions.md, which the
# SessionStart hook injects (and autodev.md references) — so the dev persona inherits
# "use the generated types, use the theme" as BINDING context instead of hand-rolling
# types and hardcoding styles. The team's own AGENTS.md/CLAUDE.md still wins on conflict.

New string:
# autoDev — convention auto-detector. Scans the TARGET repo for the house patterns
# a fresh-context dev agent would otherwise reinvent (generated types, design
# system/theme, data layer, testing) and emits a prescriptive markdown report.
# /autodev:new and /autodev:loop run this and cache the result at .autodev/conventions.md,
# reading it explicitly at the top of each run (reference/manual.md references it) — so the
# dev persona inherits "use the generated types, use the theme" as BINDING context instead
# of hand-rolling types and hardcoding styles. The team's own AGENTS.md/CLAUDE.md still wins.
```

- [ ] **Step 4: Verify no `{{` remains**

Run: `grep -n '{{' scripts/detect-conventions.sh`
Expected: no output.

- [ ] **Step 5: Smoke-test against a scratch repo**

```bash
TGT=$(mktemp -d)
echo '{"dependencies":{"react":"18","@mui/material":"5"}}' > "$TGT/package.json"
bash /Users/svickn/working/autodev/scripts/detect-conventions.sh "$TGT" | grep -q "Material UI"
echo "exit: $?"
rm -rf "$TGT"
```

Expected: `exit: 0`.

- [ ] **Step 6: Commit**

```bash
cd /Users/svickn/working/autodev
git add scripts/detect-conventions.sh
git commit -m "feat(plugin): relocate detect-conventions.sh, drop the {{CMD_LINT}} placeholder"
```

---

### Task 4: Port `doctor.sh` (drop the engine-version-staleness check)

The old `doctor.sh` warned when the installed engine (stamped into `.autodev/deployment.json` by `install.sh`) was older than the engine repo. There is no more install-time stamping and no more "engine repo" to compare against — a plugin updates itself. That whole section is removed.

**Files:**
- Move: `template/scripts/doctor.sh` → `scripts/doctor.sh`

**Interfaces:**
- Produces: `scripts/doctor.sh` — preflight check, exits 0/PASS or 1/FAIL. Consumes `scripts/tracker.mjs`, `scripts/linear.mjs`, `scripts/check-docs.sh` via `$HERE/<name>` (same directory — works unchanged since they're all siblings under `scripts/`).

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/scripts/doctor.sh scripts/doctor.sh
chmod +x scripts/doctor.sh
```

- [ ] **Step 2: Remove the engine-version-staleness section**

```
Old string:
echo "engine version:"
INST_V=$(jq -r '.engine.version // "unstamped"' "$CONFIG")
INST_SHA=$(jq -r '.engine.sha // "?"' "$CONFIG")
ENG_DIR=$(jq -r '.engine.engine_dir // ""' "$CONFIG")
if [[ "$INST_V" == "unstamped" ]]; then
  warn "install is unstamped (pre-1.1.0 engine) — re-run install.sh to upgrade + stamp"
elif [[ -n "$ENG_DIR" && -f "$ENG_DIR/VERSION" ]]; then
  CUR_V=$(cat "$ENG_DIR/VERSION")
  CUR_SHA=$(git -C "$ENG_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
  if [[ "$CUR_V" == "$INST_V" && "$CUR_SHA" == "$INST_SHA" ]]; then
    ok "current ($INST_V @ $INST_SHA)"
  else
    warn "STALE install: this repo has $INST_V @ $INST_SHA, engine repo is $CUR_V @ $CUR_SHA — re-run: $ENG_DIR/install.sh (or --all)"
  fi
else
  ok "installed $INST_V @ $INST_SHA (engine repo not reachable to compare)"
fi

echo "repo:"

New string:
echo "repo:"
```

- [ ] **Step 3: Fix the header comment**

```
Old string:
#!/usr/bin/env bash
# autoDev — preflight. Fail fast on setup mistakes BEFORE a run.
# Client-agnostic: reads .autodev/deployment.json. Run from anywhere in the repo.

New string:
#!/usr/bin/env bash
# autoDev — preflight. Fail fast on setup mistakes BEFORE a run.
# Client-agnostic: reads .autodev/deployment.json. Run from anywhere in the repo.
# Invoked by /autodev:init and available any time as ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh.
```

- [ ] **Step 4: Verify no `{{` remains and the engine-version block is gone**

Run: `grep -n '{{\|engine.version\|engine_dir' scripts/doctor.sh`
Expected: no output.

- [ ] **Step 5: Smoke-test against a scratch repo (expect it to run, not necessarily PASS — depends on installed tools)**

```bash
TGT=$(mktemp -d) && git -C "$TGT" init -q
mkdir -p "$TGT/.autodev"
jq '.client_name="ScratchCo" | .tracker.kind="local" | .repo.local_path=$p' --arg p "$TGT" \
  /Users/svickn/working/autodev/config/deployment.example.json > "$TGT/.autodev/deployment.json"
bash /Users/svickn/working/autodev/scripts/doctor.sh "$TGT" 2>&1 | tail -20
rm -rf "$TGT"
```

Wait — `doctor.sh` resolves its own root via `git rev-parse --show-toplevel`, not an argument; run it from inside `$TGT` instead:

```bash
TGT=$(mktemp -d) && git -C "$TGT" init -q
mkdir -p "$TGT/.autodev"
jq '.client_name="ScratchCo" | .tracker.kind="local" | .repo.local_path=$p' --arg p "$TGT" \
  /Users/svickn/working/autodev/config/deployment.example.json > "$TGT/.autodev/deployment.json"
(cd "$TGT" && bash /Users/svickn/working/autodev/scripts/doctor.sh) 2>&1 | tail -20
rm -rf "$TGT"
```

Expected: prints `autoDev doctor — .../deployment.json` and a series of ✓/✗/! lines, ending in `doctor: PASS` or `doctor: FAIL` (either is fine for this smoke check — the point is it runs to completion).

- [ ] **Step 6: Commit**

```bash
cd /Users/svickn/working/autodev
git add scripts/doctor.sh
git commit -m "feat(plugin): relocate doctor.sh, drop the install.sh-era engine-version check"
```

---

### Task 5: Port `reference/story-template.md` (no changes needed)

**Files:**
- Move: `template/.claude/skills/_story-template.md` → `reference/story-template.md`

**Interfaces:**
- Produces: `reference/story-template.md`, read by `reference/breakdown.md` (Task 7).

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/.claude/skills/_story-template.md reference/story-template.md
```

- [ ] **Step 2: Update its self-referential header (it's no longer file-named with a leading underscore, and "/breakdown" isn't a command anymore)**

```
Old string:
# Story template (used by /breakdown)

New string:
# Story template (used by the breakdown stage — reference/breakdown.md)
```

- [ ] **Step 3: Verify no `{{` present (sanity check — none expected)**

Run: `grep -n '{{' reference/story-template.md`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
cd /Users/svickn/working/autodev
git add reference/story-template.md
git commit -m "feat(plugin): port story-template.md into reference/"
```

---

### Task 6: Port `reference/prd.md`

Simplest doc port — only the frontmatter needs to go (no `{{TOKEN}}` in the body, no command cross-references).

**Files:**
- Move: `template/.claude/skills/prd.md` → `reference/prd.md`

**Interfaces:**
- Produces: `reference/prd.md`, read by `commands/loop.md` (Task 15).

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/.claude/skills/prd.md reference/prd.md
```

- [ ] **Step 2: Strip the auto-match frontmatter**

```
Old string:
---
name: prd
description: >
  Turn a captured brief into an approved PRD for {{CLIENT_NAME}}. Use after
  intake — when the operator says "draft the PRD", "let's spec X", or "the brief
  is ready". Produces a PRD (BrainGrid Requirement, or agent-authored fallback)
  and stops at Gate 1 for the operator's approval. Interactive, human-in-the-loop.
---

# PRD — author the spec, stop at Gate 1

New string:
# PRD — author the spec, stop at Gate 1

> Read by `/autodev:loop` when a feature has a captured brief but no PRD yet, or by
> `/autodev:new` on the BYO-PRD fast path. Not independently invokable.
```

- [ ] **Step 3: Verify no `{{` and no YAML frontmatter remains**

Run: `head -5 reference/prd.md && grep -n '{{' reference/prd.md`
Expected: first line is `# PRD — author the spec, stop at Gate 1`; no `{{` matches.

- [ ] **Step 4: Commit**

```bash
cd /Users/svickn/working/autodev
git add reference/prd.md
git commit -m "feat(plugin): port prd.md into reference/, drop auto-match frontmatter"
```

---

### Task 7: Port `reference/breakdown.md`

**Files:**
- Move: `template/.claude/skills/breakdown.md` → `reference/breakdown.md`

**Interfaces:**
- Produces: `reference/breakdown.md`, read by `commands/loop.md` (Task 15). Reads `reference/story-template.md` (Task 5).

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/.claude/skills/breakdown.md reference/breakdown.md
```

- [ ] **Step 2: Strip the auto-match frontmatter, replace with a plain intro**

```
Old string:
---
name: breakdown
description: >
  Break an approved PRD into Linear stories for {{CLIENT_NAME}}. Use after
  Gate 1 — when the operator approves the PRD / moves the epic out of PRD Review.
  Runs BrainGrid /breakdown, then copies each task's FULL spec into a
  self-contained Linear issue (so the dev agent never reads BrainGrid), adding
  persona routing, risk class, AI-QA steps, and manual test steps.
---

# Breakdown — Requirement → Linear stories

New string:
# Breakdown — Requirement → Linear stories

> Read by `/autodev:loop` after Gate 1 — when the operator approves the PRD / moves
> the epic out of PRD Review. Runs BrainGrid `/breakdown`, then copies each task's
> FULL spec into a self-contained Linear issue (so the dev agent never reads
> BrainGrid), adding persona routing, risk class, AI-QA steps, and manual test steps.
> Not independently invokable.

New string:
# Breakdown — Requirement → Linear stories

> Read by `/autodev:loop` after Gate 1 — when the operator approves the PRD / moves
> the epic out of PRD Review. Runs BrainGrid `/breakdown`, then copies each task's
> FULL spec into a self-contained Linear issue (so the dev agent never reads
> BrainGrid), adding persona routing, risk class, AI-QA steps, and manual test steps.
> Not independently invokable.
```

(Only write the second `New string` block once — the duplication above is a copy-paste artifact of drafting; the file should end up with exactly one `# Breakdown` heading followed by the blockquote.)

- [ ] **Step 3: Apply the token-to-config-path substitution**

```bash
cd /Users/svickn/working/autodev
sed -i.bak \
  -e "s|{{FEATURE_PREFIX}}|\`repo.feature_branch_prefix\`|g" \
  -e "s|{{DEFAULT_BRANCH}}|\`repo.default_branch\`|g" \
  -e "s|{{LINEAR_TEAM}}|\`tracker.team\`|g" \
  -e "s#scripts/autodev/#\${CLAUDE_PLUGIN_ROOT}/scripts/#g" \
  reference/breakdown.md
rm -f reference/breakdown.md.bak
```

- [ ] **Step 4: Verify no `{{` and no raw `scripts/autodev/` remains**

Run: `grep -n '{{' reference/breakdown.md; grep -n 'scripts/autodev/' reference/breakdown.md`
Expected: no output from either.

- [ ] **Step 5: Commit**

```bash
cd /Users/svickn/working/autodev
git add reference/breakdown.md
git commit -m "feat(plugin): port breakdown.md into reference/"
```

---

### Task 8: Port `reference/intake.md`

**Files:**
- Move: `template/.claude/skills/intake.md` → `reference/intake.md`

**Interfaces:**
- Produces: `reference/intake.md`, read by `commands/new.md` (Task 14) and `commands/loop.md` (Task 15, linear-mode front half).

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/.claude/skills/intake.md reference/intake.md
```

- [ ] **Step 2: Strip the auto-match frontmatter**

```
Old string:
---
name: intake
description: >
  The front door for new work on {{CLIENT_NAME}}. Use whenever the operator wants
  to add a feature, fix, or idea to the roadmap — e.g. "we need to add X", "new
  idea for the roadmap", "here's a brief for Y". Routes the request, interviews
  for anything missing, and creates the Linear feature-request issue. The ONLY way work
  enters the engine.
---

# Intake — the only entry point

New string:
# Intake — the only entry point

> Read by `/autodev:new`, the only way work enters the engine — never auto-triggered
> by conversation. Routes the request, interviews for anything missing, and creates
> the feature-request issue.
```

- [ ] **Step 3: Update the two `/prd` / `/breakdown` cross-references (no longer standalone commands)**

```
Old string:
5. **Hand off.** Tell the operator the brief is captured and offer to draft the
   PRD next (the `/prd` skill turns this into a BrainGrid Requirement for their
   Gate 1 approval). Do not proceed past intake without the operator.

New string:
5. **Hand off.** Tell the operator the brief is captured and offer to draft the
   PRD next (running `/autodev:loop` turns this into a BrainGrid Requirement for
   their Gate 1 approval, per `reference/prd.md`). Do not proceed past intake
   without the operator.
```

```
Old string:
   One operator `approve` = **Gate 1**. Skip `/prd` authoring (their document IS
   the PRD — file it as such); on approval go straight to `/breakdown`. Ask-don't-
   invent still applies: a PRD too thin for testable criteria gets its gaps listed
   in the package, not silently guessed.

New string:
   One operator `approve` = **Gate 1**. Skip PRD authoring (their document IS
   the PRD — file it as such); on approval the next `/autodev:loop` goes straight
   to breakdown (`reference/breakdown.md`). Ask-don't-invent still applies: a PRD
   too thin for testable criteria gets its gaps listed in the package, not
   silently guessed.
```

```
Old string:
- Do not create stories, branches, projects, milestones, or BrainGrid tasks here
  — intake only produces the brief + the feature-request issue. The full
  hierarchy comes at `/breakdown`, after the PRD is approved at Gate 1.

New string:
- Do not create stories, branches, projects, milestones, or BrainGrid tasks here
  — intake only produces the brief + the feature-request issue. The full
  hierarchy comes from `/autodev:loop`'s breakdown stage, after the PRD is
  approved at Gate 1.
```

- [ ] **Step 4: Apply the token-to-config-path substitution**

```bash
cd /Users/svickn/working/autodev
sed -i.bak \
  -e "s|{{DEFAULT_BRANCH}}|\`repo.default_branch\`|g" \
  -e "s|{{LINEAR_TEAM}}|\`tracker.team\`|g" \
  -e "s#scripts/autodev/#\${CLAUDE_PLUGIN_ROOT}/scripts/#g" \
  reference/intake.md
rm -f reference/intake.md.bak
```

- [ ] **Step 5: Verify**

Run: `grep -n '{{\|scripts/autodev/\|`/prd`\|`/breakdown`' reference/intake.md`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
cd /Users/svickn/working/autodev
git add reference/intake.md
git commit -m "feat(plugin): port intake.md into reference/"
```

---

### Task 9: Port `reference/merge-verify.md`

**Files:**
- Move: `template/.claude/skills/merge-verify.md` → `reference/merge-verify.md`

**Interfaces:**
- Produces: `reference/merge-verify.md`, read inline from `reference/devloop.md` (Task 10) after every squash-merge, and from `commands/loop.md` at feature close-out.

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/.claude/skills/merge-verify.md reference/merge-verify.md
```

- [ ] **Step 2: Strip the auto-match frontmatter and fix the `/devloop` cross-reference in the intro**

```
Old string:
---
name: merge-verify
description: >
  Clean-room integration check after a merge. Reproduces CI/prod conditions
  (fresh checkout, clean install, full suite + build + e2e + live smoke) so
  "worked on my machine" can't slip through. Auto-reverts a bad merge and
  generates the report that backs the human's final prod sign-off.
---

# merge-verify — prove it works AFTER the merge, not just on the story branch

A story branch passing in isolation is NOT proof the *integrated* result works.
This is the engine's answer to classic "it worked on my local." Invoked by
`/devloop` after a squash-merge into the feature branch, and as the gate around
the human merge to `{{DEFAULT_BRANCH}}`.

New string:
# merge-verify — prove it works AFTER the merge, not just on the story branch

> Read inline from `reference/devloop.md` after every squash-merge, and from
> `/autodev:loop`'s feature close-out step. Not independently invokable.

A story branch passing in isolation is NOT proof the *integrated* result works.
This is the engine's answer to classic "it worked on my local." Invoked by
`/autodev:loop` after a squash-merge into the feature branch, and as the gate around
the human merge to `{{DEFAULT_BRANCH}}`.
```

- [ ] **Step 3: Fix the pre-push-hook reference in Guardrails**

```
Old string:
- Per **Delivery mode**: `draft_pr` → the bot pushes `{{FEATURE_PREFIX}}*` /
  `{{STORY_PREFIX}}/*` and may squash story→feature, but NEVER merges into
  `{{DEFAULT_BRANCH}}` (needs bot git identity + branch protection). `local_diff` →
  the bot pushes **nothing** (enforced by `.git/hooks/pre-push`); it squashes
  story→feature **locally** and never merges `{{DEFAULT_BRANCH}}`.

New string:
- Per **Delivery mode**: `draft_pr` → the bot pushes `{{FEATURE_PREFIX}}*` /
  `{{STORY_PREFIX}}/*` and may squash story→feature, but NEVER merges into
  `{{DEFAULT_BRANCH}}` (needs bot git identity + branch protection). `local_diff` →
  the bot pushes **nothing** (enforced by the plugin's `PreToolUse` push-guard
  hook); it squashes story→feature **locally** and never merges `{{DEFAULT_BRANCH}}`.
```

- [ ] **Step 4: Apply the token-to-config-path substitution**

```bash
cd /Users/svickn/working/autodev
sed -i.bak \
  -e "s|{{DEFAULT_BRANCH}}|\`repo.default_branch\`|g" \
  -e "s|{{CMD_INSTALL}}|\`commands.install\`|g" \
  -e "s|{{CMD_LINT}}|\`commands.lint\`|g" \
  -e "s|{{CMD_BUILD}}|\`commands.build\`|g" \
  -e "s|{{CMD_APP_RUN}}|\`commands.app_run\`|g" \
  -e "s|{{APP_URL}}|\`commands.app_url\`|g" \
  -e "s|{{E2E_DIR}}|\`qa.e2e_dir\`|g" \
  -e "s|{{FEATURE_PREFIX}}|\`repo.feature_branch_prefix\`|g" \
  -e "s|{{STORY_PREFIX}}|\`repo.story_branch_prefix\`|g" \
  -e "s#scripts/autodev/#\${CLAUDE_PLUGIN_ROOT}/scripts/#g" \
  reference/merge-verify.md
rm -f reference/merge-verify.md.bak
```

- [ ] **Step 5: Verify**

Run: `grep -n '{{\|pre-push\|`/devloop`' reference/merge-verify.md`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
cd /Users/svickn/working/autodev
git add reference/merge-verify.md
git commit -m "feat(plugin): port merge-verify.md into reference/"
```

---

### Task 10: Port `reference/devloop.md`

The largest, most cross-referenced doc. Frontmatter strip, token substitution, plus five substantive cross-reference fixes (`.claude/autodev.md`, `/intake`, `/prd`, `/breakdown`, `/merge-verify` mentions).

**Files:**
- Move: `template/.claude/skills/devloop.md` → `reference/devloop.md`

**Interfaces:**
- Produces: `reference/devloop.md`, read by `commands/loop.md` (Task 15) as the default "do the next heartbeat" step. Reads `reference/manual.md` (Task 11), `reference/intake.md` (Task 8), `reference/prd.md` (Task 6), `reference/breakdown.md` (Task 7), `reference/merge-verify.md` (Task 9).

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/.claude/skills/devloop.md reference/devloop.md
```

- [ ] **Step 2: Strip the auto-match frontmatter**

```
Old string:
---
name: devloop
description: >
  One autonomous heartbeat pass of the {{CLIENT_NAME}} dev engine. Invoked by the
  timer (claude -p "/devloop") or manually to advance work. Stateless and
  idempotent — reads all state from the board + git, does one bounded unit of
  work, writes results back, exits. Honors the per_story / per_feature review
  toggle.
---

# devloop — one heartbeat pass

Read `.autodev/deployment.json` for: tracker states/labels, `execution.*`
(max_lanes, max_dev_qa_loops, self_review_rounds, logging), `review.*`,
`personas.*` (dev_routing, qa_angles), `commands.*`, `qa.*`, `backup.*`, branch names.
The rate-limit gate, flock, and heartbeat touch live in the wrapper
(`scripts/autodev/devloop-tick.sh`); this skill is the work of one pass.

New string:
# devloop — one heartbeat pass

> Read by `/autodev:loop` — its default step whenever no PRD/breakdown/front-half
> action is pending. Invoked by the timer headlessly (`claude -p "/autodev:loop"`)
> or manually. Stateless and idempotent — reads all state from the board + git,
> does one bounded unit of work, writes results back, exits. Honors the
> per_story / per_feature review toggle. Not independently invokable.

Read `.autodev/deployment.json` for: tracker states/labels, `execution.*`
(max_lanes, max_dev_qa_loops, self_review_rounds, logging), `review.*`,
`personas.*` (dev_routing, qa_angles), `commands.*`, `qa.*`, `backup.*`, branch names.
The rate-limit gate, flock, and heartbeat touch live in the wrapper
(`${CLAUDE_PLUGIN_ROOT}/scripts/devloop-tick.sh`); this doc is the work of one pass.
```

- [ ] **Step 3: Fix the `/intake` / `/prd` / `/breakdown` cross-references in §0**

```
Old string:
- **New request:** issue in `intake.linear_drop_status` (standard: `New Request`)
  without `ai-eligible`, **created after this engine's install
  (`.engine.installed_at`) by an authorized operator** — pre-existing backlog is not
  auto-adopted (principle 10; on the drop-zone pickup the engine applies
  `tracker.instance_label`) → run **`/intake`** in linear mode: classify. **Feature** →
  post the first clarifying question(s), move to `Clarifying (H)`. **Bug/task** →
  comment the flag, label `route:bug`/`route:task`, leave for human triage — do not
  build (unless `intake.bugs: pipeline` — see `/intake`).
- **Operator replied** (issue in `Clarifying (H)`, latest comment from an authorized
  operator) → ask the next question, or if the brief is complete author the PRD
  (`/prd`), post a plain-English summary, move to `PRD Review (H)` with "reply
  `approve` to proceed, or tell me changes."
- **Gate 1 `approve`** (in `PRD Review (H)`, from an authorized operator) → log the
  audit comment, run **`/breakdown`**.

New string:
- **New request:** issue in `intake.linear_drop_status` (standard: `New Request`)
  without `ai-eligible`, **created after this repo's `.autodev/deployment.json` was
  written by an authorized operator** — pre-existing backlog is not auto-adopted
  (principle 10; on the drop-zone pickup the engine applies `tracker.instance_label`)
  → follow **`reference/intake.md`**'s linear-mode steps: classify. **Feature** →
  post the first clarifying question(s), move to `Clarifying (H)`. **Bug/task** →
  comment the flag, label `route:bug`/`route:task`, leave for human triage — do not
  build (unless `intake.bugs: pipeline` — see `reference/intake.md`).
- **Operator replied** (issue in `Clarifying (H)`, latest comment from an authorized
  operator) → ask the next question, or if the brief is complete author the PRD
  (`reference/prd.md`), post a plain-English summary, move to `PRD Review (H)` with
  "reply `approve` to proceed, or tell me changes."
- **Gate 1 `approve`** (in `PRD Review (H)`, from an authorized operator) → log the
  audit comment, run breakdown (`reference/breakdown.md`).
```

- [ ] **Step 4: Fix the `.claude/autodev.md` cross-reference in §3**

```
Old string:
- Spawn the story's **`agent:` persona** (breakdown / `dev_routing`) as the dev
  subagent in its **own git worktree**, story branch `{{STORY_PREFIX}}/sc-<id>/<slug>`
  cut from feature-branch HEAD. Fresh context — **the spawn prompt MUST include the
  universal coding standards (`.claude/autodev.md` ▸ Coding standards)**; the subagent

New string:
- Spawn the story's **`agent:` persona** (breakdown / `dev_routing`) as the dev
  subagent in its **own git worktree**, story branch `{{STORY_PREFIX}}/sc-<id>/<slug>`
  cut from feature-branch HEAD. Fresh context — **the spawn prompt MUST include the
  universal coding standards (`${CLAUDE_PLUGIN_ROOT}/reference/manual.md` ▸ Coding
  standards)**; the subagent
```

- [ ] **Step 5: Fix the two `/merge-verify` cross-references (§7 and §8)**

```
Old string:
**After ANY squash-merge, run `/merge-verify` §1** — clean-room integration check
(fresh checkout + clean install + full gates + live smoke). On fail it auto-reverts
the merge and reopens the story: a green story branch is not proof the *integrated*
branch works.

New string:
**After ANY squash-merge, run `reference/merge-verify.md` §1** — clean-room
integration check (fresh checkout + clean install + full gates + live smoke). On
fail it auto-reverts the merge and reopens the story: a green story branch is not
proof the *integrated* branch works.
```

```
Old string:
- **Run `/merge-verify` §2** — whole-feature acceptance QA (integrated suites + live
  system smoke) → **acceptance report** → the acceptance gate.

New string:
- **Run `reference/merge-verify.md` §2** — whole-feature acceptance QA (integrated
  suites + live system smoke) → **acceptance report** → the acceptance gate.
```

```
Old string:
- **After the human merges to `{{DEFAULT_BRANCH}}`:** `/merge-verify` §3 — post-deploy
  smoke on the real environment → report → **human final prod sign-off**.

New string:
- **After the human merges to `{{DEFAULT_BRANCH}}`:** `reference/merge-verify.md` §3 —
  post-deploy smoke on the real environment → report → **human final prod sign-off**.
```

- [ ] **Step 6: Apply the token-to-config-path substitution**

```bash
cd /Users/svickn/working/autodev
sed -i.bak \
  -e "s|{{CLIENT_NAME}}|this deployment|g" \
  -e "s|{{CMD_TEST}}|\`commands.test\`|g" \
  -e "s|{{CMD_LINT}}|\`commands.lint\`|g" \
  -e "s|{{CMD_APP_RUN}}|\`commands.app_run\`|g" \
  -e "s|{{APP_URL}}|\`commands.app_url\`|g" \
  -e "s|{{STORY_PREFIX}}|\`repo.story_branch_prefix\`|g" \
  -e "s|{{FEATURE_PREFIX}}|\`repo.feature_branch_prefix\`|g" \
  -e "s|{{DEFAULT_BRANCH}}|\`repo.default_branch\`|g" \
  -e "s#scripts/autodev/#\${CLAUDE_PLUGIN_ROOT}/scripts/#g" \
  reference/devloop.md
rm -f reference/devloop.md.bak
```

- [ ] **Step 7: Verify**

Run: `grep -n '{{\|`/intake`\|`/prd`\|`/breakdown`\|`/merge-verify`\|`/devloop`\|\.claude/autodev\.md' reference/devloop.md`
Expected: no output.

- [ ] **Step 8: Commit**

```bash
cd /Users/svickn/working/autodev
git add reference/devloop.md
git commit -m "feat(plugin): port devloop.md into reference/"
```

---

### Task 11: Port `reference/manual.md` (the engine manual — largest rewrite)

**Files:**
- Move: `template/.claude/autodev.md` → `reference/manual.md`

**Interfaces:**
- Produces: `reference/manual.md`, read explicitly at the top of `commands/new.md`, `commands/loop.md`, and `commands/init.md`.

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv template/.claude/autodev.md reference/manual.md
```

- [ ] **Step 2: Fix the title**

```
Old string:
# {{CLIENT_NAME}} — autoDev engine manual (`.claude/autodev.md`)

New string:
# autoDev engine manual (`reference/manual.md`)
```

- [ ] **Step 3: Fix the "own files" callout**

```
Old string:
> **Never edit, overwrite, or "update" `AGENTS.md` / `CLAUDE.md`** — autoDev lives in its
> own files (`.claude/autodev.md`, `.claude/skills/*`, `.autodev/`) and treats theirs as
> read-only. If a convention genuinely needs changing, **propose it in a separate PR with
> a rationale** (see non-negotiable 11) — never a silent in-place edit.
>
> Unsure of current state? Run `node scripts/autodev/tracker.mjs doctor` and read the board
> first. The one exception to all of the above is when the operator explicitly asks you to
> work on the **autoDev engine itself**.

New string:
> **Never edit, overwrite, or "update" `AGENTS.md` / `CLAUDE.md`** — autoDev lives in its
> own files (the plugin's `reference/*` docs, `.autodev/`) and treats theirs as
> read-only. If a convention genuinely needs changing, **propose it in a separate PR with
> a rationale** (see non-negotiable 11) — never a silent in-place edit.
>
> Unsure of current state? Run `node "${CLAUDE_PLUGIN_ROOT}/scripts/tracker.mjs" doctor`
> and read the board first. The one exception to all of the above is when the operator
> explicitly asks you to work on the **autoDev engine itself**.
```

- [ ] **Step 4: Rewrite the intro paragraph — no more ambient routing from plain conversation**

```
Old string:
This repo runs **autoDev**: an autonomous development engine driven by Claude
Code. **Your name is {{ASSISTANT_NAME}}** — that's who the operator is talking to;
introduce yourself and sign off as {{ASSISTANT_NAME}}. You (the operator) talk to it
in plain English; it turns approved PRDs into QA'd, human-reviewable code through
Linear, with two human gates.

You never need to remember a command. Just say what you want — the routing
below maps your intent to the right skill. (Slash commands `/intake` `/prd`
`/breakdown` `/devloop` exist as power-user shortcuts.)

New string:
This repo runs **autoDev**: an autonomous development engine driven by Claude
Code. **Your name is {{ASSISTANT_NAME}}** — that's who the operator is talking to;
introduce yourself and sign off as {{ASSISTANT_NAME}}. The operator talks to it
in plain English; it turns approved PRDs into QA'd, human-reviewable code through
the board, with two human gates.

Two commands drive everything — **nothing runs from plain conversation alone.**
**`/autodev:new`** captures new work (feature, bug, brief, or a finished PRD).
**`/autodev:loop`** advances whatever's next — PRD, breakdown, one dev/QA
heartbeat, or merge-verify — based on live board state; re-run it to keep
advancing. Both bootstrap `.autodev/deployment.json` automatically the first
time (or run `/autodev:init` explicitly). The table below describes what each
command does with what the operator just said — it is not a list of things
that happen on their own.
```

- [ ] **Step 5: Rewrite the concierge routing table**

```
Old string:
On a new session, greet **as {{ASSISTANT_NAME}}** with a short status snapshot (read
from Linear): what shipped overnight, what's waiting on them (gates + Blocked
questions), what's in flight. Then route intent:

| The operator says (any phrasing) | Do this |
|---|---|
| "We need to add a feature…" / "new idea for the roadmap" | Run **`/intake`** — interview for problem, solution, users, priority, timeline |
| "X is broken" / "this should work but doesn't" / "it exports blank / errors" | Run **`/intake`** — it classifies this as a **bug** and honors `intake.bugs`: `triage` (default) = flag `route:bug` for human triage, don't build; `pipeline` = interview for a full **reproduction** and run the repro-test-first bug pipeline (failing test → fix → green). |
| "Here's the brief for X" | `/intake` → then `/prd` — draft the Requirement, walk them through it |
| "Here's the PRD/spec" (a finished document) | `/intake` **BYO-PRD fast path** — analyze it, reply with ONE approval package (≤10-line summary + only the gaps that change what gets built). Their `approve` = Gate 1 → `/breakdown` → build starts. No re-interview, no `/prd` re-authoring. |
| "The PRD looks good" / "approved" | Log **Gate 1** approval → move the epic → run **`/breakdown`** |
| "What's the status?" / "what happened overnight?" | Read the board (`tracker.mjs board` / Linear) → plain-English report: shipped, in QA, blocked, and whether the engine is rate-limited (paused, auto-resuming at <time>) |
| "What do you need from me?" | List Blocked-column questions + cards waiting at gates |
| "Ticket X works" / "ticket X is broken because…" | Log the **Gate 2** verdict, move the issue, post their comment |
| "Grab ticket X off the board" / "can you take ADX-42?" | **Adopt it** (principle 10's operator hand-over): read it, run `/intake` on its content (confirm, don't re-interview what it already answers; it still needs testable criteria), apply `tracker.instance_label` — then it's owned and flows the full pipeline like any engine-created ticket |
| "Pause everything" | Disable the timer; explain how to resume |
| Anything ambiguous | Ask a clarifying question — never expect a command name |

New string:
When `/autodev:new` or `/autodev:loop` runs, open with a short status snapshot
(read from the board): what shipped overnight, what's waiting on them (gates +
Blocked questions), what's in flight. Then act on what the operator said:

| Command | The operator says (any phrasing) | Do this |
|---|---|---|
| `/autodev:new` | "We need to add a feature…" / "new idea for the roadmap" | Interview for problem, solution, users, priority, timeline (`reference/intake.md`) |
| `/autodev:new` | "X is broken" / "this should work but doesn't" / "it exports blank / errors" | Classify as a **bug** and honor `intake.bugs`: `triage` (default) = flag `route:bug` for human triage, don't build; `pipeline` = interview for a full **reproduction** and run the repro-test-first bug pipeline (failing test → fix → green). |
| `/autodev:new` | "Here's the brief for X" | Capture the brief; the next `/autodev:loop` drafts the PRD (`reference/prd.md`) |
| `/autodev:new` | "Here's the PRD/spec" (a finished document) | **BYO-PRD fast path** — analyze it, reply with ONE approval package (≤10-line summary + only the gaps that change what gets built). Their `approve` on the next `/autodev:loop` = Gate 1 → breakdown starts. No re-interview, no PRD re-authoring. |
| `/autodev:new` | "Grab ticket X off the board" / "can you take ADX-42?" | **Adopt it** (principle 10's operator hand-over): read it, run intake on its content (confirm, don't re-interview what it already answers; it still needs testable criteria), apply `tracker.instance_label` — then it's owned and flows the full pipeline like any engine-created ticket |
| `/autodev:loop` | "The PRD looks good" / "approved" | Log **Gate 1** approval → move the epic → run breakdown (`reference/breakdown.md`) |
| `/autodev:loop` | "Ticket X works" / "ticket X is broken because…" | Log the **Gate 2** verdict, move the issue, post their comment |
| `/autodev:loop` | (no special phrasing) | Reconcile the board, then do the next bounded unit of work — see `reference/devloop.md` |
| — | "What's the status?" / "what do you need from me?" | Answer directly from the board (`tracker.mjs board`) — a plain read, no command required |
| — | "Pause everything" | Explain how to disable the timer (see the 24/7 timer docs); does not touch the board |
```

- [ ] **Step 6: Fix the `install-time check-docs.sh` reference**

```
Old string:
**First-session reconciliation (once — if `.autodev/.docs_reconciled` is absent).** Before
any work, if the repo has an `AGENTS.md` or team `CLAUDE.md`, **read it and check it against
the workflow non-negotiables** (the board is the only state machine · two human gates · only
humans merge the default branch · tests ship with every change · ask-don't-invent). The
install-time `check-docs.sh` is a keyword heuristic; you do the *semantic* pass it can't.

New string:
**First-session reconciliation (once — if `.autodev/.docs_reconciled` is absent).** Before
any work, if the repo has an `AGENTS.md` or team `CLAUDE.md`, **read it and check it against
the workflow non-negotiables** (the board is the only state machine · two human gates · only
humans merge the default branch · tests ship with every change · ask-don't-invent). The
`check-docs.sh` heuristic (run by `/autodev:init`) is a keyword scan; you do the *semantic*
pass it can't.
```

- [ ] **Step 7: Fix the "adopting a ticket" cross-reference in this same paragraph**

```
Old string:
If you find a rule that fights the workflow (e.g. "commit straight to main", "skip tests",
"self-merge", "act without asking"), **surface it to the operator in plain English and ask
how to reconcile** — remind them of the split (their file governs *coding conventions*;
autoDev governs *process*), and never silently override their file or quietly drop a
non-negotiable. When reconciled (or if there's nothing to flag), `touch
.autodev/.docs_reconciled` so this doesn't repeat. Report what you found as part of the
greeting. **Also on first connect (`tracker.kind: linear`):** if the board already has
tickets without this instance's `tracker.instance_label`, don't assume — ask once:
*"I see <N> existing tickets on this board — want me to start with any of those, or
shall we spin up my own work?"* (principle 10; adopting = `/intake` + the label).

New string:
If you find a rule that fights the workflow (e.g. "commit straight to main", "skip tests",
"self-merge", "act without asking"), **surface it to the operator in plain English and ask
how to reconcile** — remind them of the split (their file governs *coding conventions*;
autoDev governs *process*), and never silently override their file or quietly drop a
non-negotiable. When reconciled (or if there's nothing to flag), `touch
.autodev/.docs_reconciled` so this doesn't repeat. Report what you found as part of the
greeting. **Also on first connect (`tracker.kind: linear`):** if the board already has
tickets without this instance's `tracker.instance_label`, don't assume — ask once:
*"I see <N> existing tickets on this board — want me to start with any of those, or
shall we spin up my own work?"* (principle 10; adopting = `/autodev:new` + the label).
```

- [ ] **Step 8: Fix the ambient-updates paragraph's `{{ASSISTANT_NAME}}` reference (leave the token — sed handles it in Step 12) and the greeting mention**

No edit needed here beyond the sed pass — re-verify after Step 12 that "greet **as {{ASSISTANT_NAME}}**" text was removed already by Step 5's table rewrite (it was — the "On a new session, greet" sentence was replaced). Skip this step; it's a checkpoint, not an edit.

- [ ] **Step 9: Fix the Delivery-mode pre-push reference**

```
Old string:
- **`local_diff` (LOCAL-ONLY):** NO `git push`, NO `gh`/PRs — ever. All branches,
  commits, and merges stay **local**. Wherever a skill says "open/update a draft PR"
  or "push the branch," instead **keep the branch local and present a LOCAL DIFF**:
  put `git diff <base>...<branch>` (and `git log --stat`) on the Linear issue as the
  review artifact, with the branch name + the exact local command to view it. Gate 2
  = a human reviews that local diff and replies `approve`. "Merge to
  `{{DEFAULT_BRANCH}}`" becomes: present the assembled **local** feature branch diff;
  on a **bare `approve`** leave the merge command for the human, but on an **explicit
  "approve and merge"** the engine MAY execute the local merge itself — the human
  DECISION is the gate, the mechanics are delegable; log the audit comment
  ("merged {{FEATURE_PREFIX}}<slug> → {{DEFAULT_BRANCH}} on <name>'s approve-and-merge,
  <date>") and never push the result. CI parity is replaced by the **local**
  gates (tests/lint/build) since there's no remote CI. Enforced hard by
  `.git/hooks/pre-push` — a push attempt is a bug, not a step.

New string:
- **`local_diff` (LOCAL-ONLY):** NO `git push`, NO `gh`/PRs — ever. All branches,
  commits, and merges stay **local**. Wherever a doc says "open/update a draft PR"
  or "push the branch," instead **keep the branch local and present a LOCAL DIFF**:
  put `git diff <base>...<branch>` (and `git log --stat`) on the issue as the
  review artifact, with the branch name + the exact local command to view it. Gate 2
  = a human reviews that local diff and replies `approve`. "Merge to
  `{{DEFAULT_BRANCH}}`" becomes: present the assembled **local** feature branch diff;
  on a **bare `approve`** leave the merge command for the human, but on an **explicit
  "approve and merge"** the engine MAY execute the local merge itself — the human
  DECISION is the gate, the mechanics are delegable; log the audit comment
  ("merged {{FEATURE_PREFIX}}<slug> → {{DEFAULT_BRANCH}} on <name>'s approve-and-merge,
  <date>") and never push the result. CI parity is replaced by the **local**
  gates (tests/lint/build) since there's no remote CI. Enforced hard by the
  plugin's `PreToolUse` push-guard hook — a push attempt is a bug, not a step.
```

- [ ] **Step 10: Fix the WIP-backup pre-push reference**

```
Old string:
does **not** open the feature PR (that still happens only at close-out, §8). Under
`local_diff`, backup is a **logged no-op** — it does not override the no-push rule or
the pre-push hook (code stays fully local by design).

New string:
does **not** open the feature PR (that still happens only at close-out, §8). Under
`local_diff`, backup is a **logged no-op** — it does not override the no-push rule or
the push-guard hook (code stays fully local by design).
```

- [ ] **Step 11: Fix non-negotiable 11's enforcement parenthetical (and add the docs-guard hook cross-reference)**

```
Old string:
11. **Never touch the team's docs; propose, don't overwrite.** The team's `AGENTS.md`,
    root `CLAUDE.md`, and `.claude/CLAUDE.md` are **read-only** to the engine — they are
    the authority on coding conventions and autoDev obeys them, but **no run, story, or
    self-review ever edits, regenerates, or "freshens" them in place.** If the engine
    learns a convention worth recording or believes one should change, it opens a
    **separate, dedicated PR** titled `docs(conventions): <change>` with a **Rationale**
    section, immediately, so the devs see and decide — never a silent in-line edit folded
    into feature work. (Enforced by a settings.json `deny` on editing those paths.)

New string:
11. **Never touch the team's docs; propose, don't overwrite.** The team's `AGENTS.md`,
    root `CLAUDE.md`, and `.claude/CLAUDE.md` are **read-only** to the engine — they are
    the authority on coding conventions and autoDev obeys them, but **no run, story, or
    self-review ever edits, regenerates, or "freshens" them in place.** If the engine
    learns a convention worth recording or believes one should change, it opens a
    **separate, dedicated PR** titled `docs(conventions): <change>` with a **Rationale**
    section, immediately, so the devs see and decide — never a silent in-line edit folded
    into feature work. (Enforced by the plugin's `PreToolUse` docs-guard hook, which denies
    any Edit/Write to those paths.)
```

- [ ] **Step 12: Fix Coding-standards point 1 (SessionStart no longer injects it)**

```
Old string:
**1. The team's own `AGENTS.md` / `CLAUDE.md` — TOP authority on conventions, read-only.**
If the repo has an `AGENTS.md` (or a team-authored `CLAUDE.md`), it is the final word on
how code is written here. **Read it and obey it; never edit it** (non-negotiable 11).
Where it speaks, it overrides everything below — including this file. (The SessionStart
hook injects it; if absent, fall to 2–3.)

New string:
**1. The team's own `AGENTS.md` / `CLAUDE.md` — TOP authority on conventions, read-only.**
If the repo has an `AGENTS.md` (or a team-authored `CLAUDE.md`), it is the final word on
how code is written here. **Read it and obey it; never edit it** (non-negotiable 11).
Where it speaks, it overrides everything below — including this file. (Read it explicitly
at the start of `/autodev:new` or `/autodev:loop`; if absent, fall to 2–3.)
```

- [ ] **Step 13: Fix Coding-standards point 2 (conventions are cached + read explicitly now, not install-time-injected)**

```
Old string:
**2. Auto-detected conventions — BINDING where the team's files are silent.** Generated at
install into `.autodev/conventions.md` (re-run each install) and injected at session
start. Use the generated types, use the design system/theme, reuse existing code; the §3
"survey conventions" step verifies them against the live code before writing.

New string:
**2. Auto-detected conventions — BINDING where the team's files are silent.** Generated by
`${CLAUDE_PLUGIN_ROOT}/scripts/detect-conventions.sh` into `.autodev/conventions.md`
(cached; re-run it if the stack changes) and read explicitly at the start of
`/autodev:new` or `/autodev:loop`. Use the generated types, use the design system/theme,
reuse existing code; the §3 "survey conventions" step verifies them against the live
code before writing.
```

- [ ] **Step 14: Apply the token-to-config-path substitution for everything else**

```bash
cd /Users/svickn/working/autodev
sed -i.bak \
  -e "s|{{ASSISTANT_NAME}}|\`assistant_name\`|g" \
  -e "s|{{DEFAULT_BRANCH}}|\`repo.default_branch\`|g" \
  -e "s|{{FEATURE_PREFIX}}|\`repo.feature_branch_prefix\`|g" \
  -e "s|{{STORY_PREFIX}}|\`repo.story_branch_prefix\`|g" \
  -e "s|{{MAX_LANES}}|\`execution.max_lanes\`|g" \
  -e "s|{{SELF_REVIEW}}|\`execution.self_review_rounds\`|g" \
  -e "s|{{CMD_INSTALL}}|\`commands.install\`|g" \
  -e "s|{{CMD_TEST}}|\`commands.test\`|g" \
  -e "s|{{CMD_LINT}}|\`commands.lint\`|g" \
  -e "s|{{CMD_BUILD}}|\`commands.build\`|g" \
  -e "s|{{CMD_APP_RUN}}|\`commands.app_run\`|g" \
  -e "s|{{APP_URL}}|\`commands.app_url\`|g" \
  -e "s|{{E2E_DIR}}|\`qa.e2e_dir\`|g" \
  -e "s|{{MERGE_S2F}}|\`merge_policy.story_to_feature\`|g" \
  -e "s|{{MERGE_F2M}}|\`merge_policy.feature_to_main\`|g" \
  -e "s|{{BG_PROJECT}}|\`braingrid.project_short_id\`|g" \
  -e "s|{{LINEAR_TEAM}}|\`tracker.team\`|g" \
  -e "s#scripts/autodev/#\${CLAUDE_PLUGIN_ROOT}/scripts/#g" \
  reference/manual.md
rm -f reference/manual.md.bak
```

- [ ] **Step 15: Verify no `{{`, no `/intake`/`/prd`/`/breakdown`/`/devloop` (as bare commands), no `.git/hooks/pre-push`, no `.claude/skills` remain**

Run: `grep -n '{{\|\.git/hooks/pre-push\|\.claude/skills\|\.claude/autodev\.md' reference/manual.md`
Expected: no output.

Run: `grep -n '`/intake`\|`/prd`\|`/breakdown`' reference/manual.md`
Expected: no output (the routing table now uses `` `/autodev:new` `` / `` `/autodev:loop` `` throughout).

- [ ] **Step 16: Commit**

```bash
cd /Users/svickn/working/autodev
git add reference/manual.md
git commit -m "feat(plugin): port autodev.md into reference/manual.md, rewrite for the two-command surface"
```

---

### Task 12: Port the deployment schema reference

**Files:**
- Move: `config/deployment.example.json` → `reference/deployment.example.json`

**Interfaces:**
- Produces: `reference/deployment.example.json`, read by `commands/init.md` (Task 13) as the schema/defaults source when writing a new `.autodev/deployment.json`.

- [ ] **Step 1: Move the file**

```bash
cd /Users/svickn/working/autodev
git mv config/deployment.example.json reference/deployment.example.json
```

- [ ] **Step 2: Verify it's still valid JSON after the move**

Run: `jq . reference/deployment.example.json`
Expected: pretty-printed JSON, no error.

- [ ] **Step 3: Commit**

```bash
cd /Users/svickn/working/autodev
git add reference/deployment.example.json
git commit -m "feat(plugin): relocate deployment.example.json into reference/"
```

(Note: `config/` still contains any real, gitignored per-client `*.json` files a previous engine install may have left on disk locally — those are not touched by this task; the directory itself is removed from git tracking in Task 20 once it's confirmed empty of tracked files.)

---

### Task 13: Write `commands/init.md`

**Files:**
- Create: `commands/init.md`

**Interfaces:**
- Consumes: `reference/deployment.example.json` (Task 12), `ops/linear-setup.md` (Task 19), `ops/launchd-timer.md` (Task 19).
- Produces: `.autodev/deployment.json` in the invoking repo (runtime output, not a plugin file) — the schema every other command depends on.

- [ ] **Step 1: Write the command**

```markdown
---
description: Guided one-time setup — writes .autodev/deployment.json for this repo. Safe to re-run to reconfigure.
---

Set up autoDev for **this repo**. Safe to re-run any time to reconfigure.

1. Check for an existing `.autodev/deployment.json`. If present, tell the operator
   you're reconfiguring it (not creating fresh) and show a one-line summary of the
   current settings before continuing.
2. Detect what you can from the repo, silently, before asking anything:
   - Default branch: `git symbolic-ref --short refs/remotes/origin/HEAD` (fall back
     to the current branch via `git symbolic-ref --short HEAD`).
   - Package manager: `bun.lockb`/`bun.lock` → bun · `pnpm-lock.yaml` → pnpm ·
     `yarn.lock` → yarn · `package.json` present (else) → npm.
   - If a package manager was detected, read its `package.json` `scripts` for
     `test`, `lint`, `build`, and one of `dev`/`start`/`serve` (in that order) to
     propose `commands.*` defaults.
3. Ask the operator (one question at a time, propose the detected value as the
   default, accept a bare Enter to take it):
   - Deployment name (`client_name`) — default: the repo's directory name.
   - Assistant name (`assistant_name`) — default: `"Marj"`.
   - Default branch — default: detected above.
   - Test command (`commands.test`) — default: detected above, else ask directly.
   - Install / lint / build / run commands (`commands.install` / `commands.lint` /
     `commands.build` / `commands.app_run`) — same pattern; leave `""` if none.
   - App URL (`commands.app_url`) — default `http://localhost:3000` if a run
     command was set, else `""`.
   - Tracker (`tracker.kind`): `local` (git-native board, zero setup — recommended
     for a new deployment) or `linear` (needs a Linear team + token later).
     Default: `local`.
   - Mode: `hands-on` (review every story — recommended for a first feature) or
     `autopilot` (one PRD approval, then builds + merges to the feature branch
     autonomously until acceptance). Default: `hands-on`.
     - `hands-on` → `review.granularity: "per_story"`, `review.auto_merge_to_feature_branch: false`.
     - `autopilot` → `review.granularity: "per_feature"`, `review.auto_merge_to_feature_branch: true`.
4. Read `${CLAUDE_PLUGIN_ROOT}/reference/deployment.example.json` as the schema —
   every field it contains is valid in `.autodev/deployment.json`. Write
   `.autodev/deployment.json` with that same structure, the operator's answers
   substituted in, and everything else left at the example's defaults. In
   particular: leave `tracker.statuses.*.id` / `tracker.team_id` as
   `"FILL_AT_SETUP"` when `tracker.kind` is `linear` — those are filled by hand
   after the Linear board is created (step 6 below). Drop the `install` block
   entirely (`docs_policy` was an `install.sh`-era concept; this plugin never
   writes into `.claude/` at all, so there is nothing to preserve-vs-overwrite).
5. Create the `.autodev` runtime directories: `mkdir -p .autodev/board .autodev/logs`
   (harmless if `tracker.kind` ends up `linear` — `board/` just stays empty; the
   git-native board and the operator digest log both land here on first use).
6. Print the manual next-steps report — nothing here is automated, all of it needs
   a human with the right auth:
   - If `tracker.kind` is `linear`: point at
     `${CLAUDE_PLUGIN_ROOT}/ops/linear-setup.md` for creating the board columns +
     labels and getting a Linear API token on disk at
     `~/.config/autodev/<client_name>.linear.token`.
   - If `braingrid.enabled` (default true): run `braingrid init` in this repo,
     then set `braingrid.project_short_id` in `.autodev/deployment.json`.
   - Bot git identity + branch protection (needs repo admin): protect the default
     branch so only humans merge; the bot pushes feature/story branches only.
   - 24/7 timer (optional — skip this unless the operator asks for it): see
     `${CLAUDE_PLUGIN_ROOT}/ops/launchd-timer.md`.
7. Run `${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh` from the repo root and show the
   operator anything it flags with a ✗.
8. Confirm: "`.autodev/deployment.json` is ready. Run `/autodev:new` to capture the
   first piece of work, or `/autodev:loop` once stories are queued."
```

Write this to `commands/init.md`.

- [ ] **Step 2: Verify the frontmatter parses**

Run: `awk '/^---$/{c++} c==2{exit} c>=1' commands/init.md | head -1`
Expected: prints `---` (confirms the file opens with a valid frontmatter block).

- [ ] **Step 3: Commit**

```bash
cd /Users/svickn/working/autodev
git add commands/init.md
git commit -m "feat(plugin): add /autodev:init command"
```

---

### Task 14: Write `commands/new.md`

**Files:**
- Create: `commands/new.md`

**Interfaces:**
- Consumes: `reference/manual.md` (Task 11), `reference/intake.md` (Task 8), `commands/init.md` (Task 13, invoked inline if unconfigured).

- [ ] **Step 1: Write the command**

```markdown
---
description: Capture new work (feature, bug, or brief) — the only way work enters autoDev.
---

If `.autodev/deployment.json` doesn't exist in this repo, run the setup steps in
`${CLAUDE_PLUGIN_ROOT}/commands/init.md` first, then continue below. If it exists but
fails to parse as JSON, **stop and tell the operator** — point at the exact parse
error and the file path; do not run init over it (that would silently overwrite
whatever they were mid-editing). Only a missing file triggers the automatic bootstrap.

Read `${CLAUDE_PLUGIN_ROOT}/reference/manual.md` — it's authoritative for the workflow
(not auto-loaded, so read it explicitly here). Also read `.autodev/conventions.md` if
present (auto-detected coding conventions) — generate it first via
`${CLAUDE_PLUGIN_ROOT}/scripts/detect-conventions.sh .` if it's missing.

Then follow `${CLAUDE_PLUGIN_ROOT}/reference/intake.md` step by step against whatever
the operator just told you: `$ARGUMENTS` if given inline, otherwise ask what they
want to add (a feature idea, a bug report, a brief, a finished PRD/spec, or a board
ticket to adopt).

This is a human-in-the-loop stage — stay conversational, ask rather than guess, and
stop where `reference/intake.md` says to stop (it hands off to `/autodev:loop` for
PRD drafting; it never proceeds past intake on its own).

For coding conventions (this may touch code, e.g. writing the brief to
`specs/<slug>/brief.md`), obey any team-authored `AGENTS.md` / `CLAUDE.md`
(authoritative) plus `.autodev/conventions.md`; never edit those team files
(non-negotiable 11 — the plugin's docs-guard hook enforces this independently).
```

Write this to `commands/new.md`.

- [ ] **Step 2: Verify the frontmatter parses**

Run: `awk '/^---$/{c++} c==2{exit} c>=1' commands/new.md | head -1`
Expected: prints `---`.

- [ ] **Step 3: Commit**

```bash
cd /Users/svickn/working/autodev
git add commands/new.md
git commit -m "feat(plugin): add /autodev:new command"
```

---

### Task 15: Write `commands/loop.md`

**Files:**
- Create: `commands/loop.md`

**Interfaces:**
- Consumes: `reference/manual.md` (Task 11), `reference/prd.md` (Task 6), `reference/breakdown.md` (Task 7), `reference/devloop.md` (Task 10, which itself reads `reference/merge-verify.md`), `commands/init.md` (Task 13, invoked inline if unconfigured).

- [ ] **Step 1: Write the command**

```markdown
---
description: Advance autoDev by one bounded step — PRD, breakdown, a dev/QA heartbeat, or merge-verify, whichever is next.
---

If `.autodev/deployment.json` doesn't exist in this repo, run the setup steps in
`${CLAUDE_PLUGIN_ROOT}/commands/init.md` first, then continue below. If it exists but
fails to parse as JSON, **stop and tell the operator** — point at the exact parse
error and the file path; do not run init over it (that would silently overwrite
whatever they were mid-editing). Only a missing file triggers the automatic bootstrap.

**First, read the operating manual** at `${CLAUDE_PLUGIN_ROOT}/reference/manual.md` —
it is authoritative for the workflow (not auto-loaded, so read it explicitly here).
Also read `.autodev/conventions.md` if present — generate it first via
`${CLAUDE_PLUGIN_ROOT}/scripts/detect-conventions.sh .` if it's missing.

Then read the board + git state and determine what's next, in this order:

1. **A feature-request issue is in `PRD Review (H)` and the operator just approved
   it** (they said "approved" / "the PRD looks good" in this conversation, or
   already moved the issue themselves) → log the Gate 1 approval, then follow
   `${CLAUDE_PLUGIN_ROOT}/reference/breakdown.md`.
2. **A feature-request issue needs a PRD drafted** (a brief exists at
   `specs/<slug>/brief.md` with no PRD authored yet) → follow
   `${CLAUDE_PLUGIN_ROOT}/reference/prd.md`.
3. **`intake.mode` is `linear` or `both`** and there's front-half board activity (a
   new ticket in the drop zone, or an operator reply awaiting the next question) →
   this is covered by §0 of `reference/devloop.md` (read it — it has the
   at-most-one-front-half-action-per-tick rule and the exact routing into
   `reference/intake.md` / `reference/prd.md` / `reference/breakdown.md`).
4. **Otherwise** → run one heartbeat pass per
   `${CLAUDE_PLUGIN_ROOT}/reference/devloop.md`: reconcile the board, pick the next
   eligible story (or promote the next queued epic), dev → self-review → AI QA →
   deliver per `review.delivery`, write every result back to the board + git, then
   stop. After any squash-merge, `reference/devloop.md` itself calls into
   `${CLAUDE_PLUGIN_ROOT}/reference/merge-verify.md` §1 — follow that inline, don't
   skip it. At feature close-out it calls `reference/merge-verify.md` §2 and, after
   a human merge to the default branch, §3.

Do **one bounded unit of work** total across the above, then stop — this command is
meant to be re-run (by a human or the timer), not to loop internally until the
board is empty.

**If invoked non-interactively** (headless, e.g. by the timer):
- Use only the tools already allowed for this invocation; never wait for human
  input mid-pass — if something is genuinely blocked, move it to the Blocked
  column with the specific question and continue with other eligible work instead.
- Honor `review.delivery` exactly as `reference/manual.md` describes it (never push
  in `local_diff`; push only feature/story branches — never the default branch —
  in `draft_pr`; the plugin's `PreToolUse` push-guard hook backstops this either way).
- If the repo needs its toolchain on `PATH` first, source it (e.g.
  `source .autodev/env.sh`) before running any configured build/test commands.
```

Write this to `commands/loop.md`.

- [ ] **Step 2: Verify the frontmatter parses**

Run: `awk '/^---$/{c++} c==2{exit} c>=1' commands/loop.md | head -1`
Expected: prints `---`.

- [ ] **Step 3: Commit**

```bash
cd /Users/svickn/working/autodev
git add commands/loop.md
git commit -m "feat(plugin): add /autodev:loop command"
```

---

### Task 16: Write `hooks/hooks.json` + the three hook scripts

Replaces `session-init.sh` (full-manual injection) with a one-line ambient signal, and replaces `.git/hooks/pre-push` with two `PreToolUse` hooks: the push guard (git push to default branch) and a new docs guard (Edit/Write on `AGENTS.md`/`CLAUDE.md`), since there is no more `settings.json` to carry a `deny` rule for either.

**Files:**
- Create: `hooks/hooks.json`
- Create: `hooks/session-signal.sh`
- Create: `hooks/guard-push.sh`
- Create: `hooks/guard-docs.sh`
- Delete: `template/scripts/session-init.sh` (superseded — deleted here rather than ported)
- Delete: `template/ops/pre-push.sh` (superseded — deleted here rather than ported)

**Interfaces:**
- Produces: three hook scripts wired up in `hooks/hooks.json`, invoked automatically by Claude Code (not called directly by any command/reference doc).

- [ ] **Step 1: Write `hooks/session-signal.sh`**

```bash
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
```

Write this to `hooks/session-signal.sh`, then `chmod +x hooks/session-signal.sh`.

- [ ] **Step 2: Write `hooks/guard-push.sh`**

```bash
#!/usr/bin/env bash
# autoDev — push guard (PreToolUse hook). Blocks a Bash `git push` of the default
# branch, and blocks ALL pushes when review.delivery=local_diff — mirroring the old
# .git/hooks/pre-push guard without ever touching the repo's own git config. Reads
# .autodev/deployment.json from the tool call's cwd; fails open (allows) if autoDev
# isn't configured there. Only guards pushes made through Claude Code — a human's own
# terminal is never affected (there is no hook installed outside this plugin).
set -uo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL" == "Bash" ]] || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
echo "$CMD" | grep -qE '(^|;|&&|\|)\s*git\s+push\b' || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
CONFIG="$CWD/.autodev/deployment.json"
[[ -f "$CONFIG" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

DEFAULT_BRANCH=$(jq -r '.repo.default_branch // "main"' "$CONFIG")
DELIVERY=$(jq -r '.review.delivery // "draft_pr"' "$CONFIG")

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

if [[ "$DELIVERY" == "local_diff" ]]; then
  deny "autoDev: review.delivery=local_diff (LOCAL-ONLY mode) — never push; present a local diff instead (reference/manual.md ▸ Delivery mode)."
fi

if echo "$CMD" | grep -qE "(refs/heads/${DEFAULT_BRANCH}\b|[[:space:]:]${DEFAULT_BRANCH}([[:space:]:]|\$))"; then
  deny "autoDev: only humans merge '${DEFAULT_BRANCH}' (Gate 2 + branch protection) — the engine never pushes it."
fi

exit 0
```

Write this to `hooks/guard-push.sh`, then `chmod +x hooks/guard-push.sh`.

- [ ] **Step 3: Write `hooks/guard-docs.sh`**

```bash
#!/usr/bin/env bash
# autoDev — docs guard (PreToolUse hook). AGENTS.md / CLAUDE.md / .claude/CLAUDE.md are
# the team's authority on coding conventions; autoDev reads them and never edits them
# (reference/manual.md non-negotiable 11). Replaces the old settings.json `deny` rule
# now that autoDev ships no settings.json at all. Runs regardless of whether autoDev is
# configured in this repo — it's a hard rule, not a per-deployment toggle.
set -uo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]] || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -n "$FILE_PATH" ]] || exit 0

if echo "$FILE_PATH" | grep -qE '(^|/)(AGENTS|CLAUDE)\.md$'; then
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "autoDev never edits AGENTS.md/CLAUDE.md (reference/manual.md non-negotiable 11) — propose a convention change as a separate PR with a Rationale section instead."}}'
  exit 0
fi
exit 0
```

Write this to `hooks/guard-docs.sh`, then `chmod +x hooks/guard-docs.sh`.

- [ ] **Step 4: Write `hooks/hooks.json`**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-signal.sh\"" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/guard-push.sh\"" }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/guard-docs.sh\"" }
        ]
      }
    ]
  }
}
```

Write this to `hooks/hooks.json`.

- [ ] **Step 5: Test `guard-push.sh` — a feature-branch push is allowed**

```bash
TGT=$(mktemp -d) && mkdir -p "$TGT/.autodev"
jq '.repo.default_branch="main" | .review.delivery="draft_pr"' \
  /Users/svickn/working/autodev/reference/deployment.example.json > "$TGT/.autodev/deployment.json"
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin feature/x\"},\"cwd\":\"$TGT\"}" \
  | /Users/svickn/working/autodev/hooks/guard-push.sh
echo "exit: $?"
rm -rf "$TGT"
```

Expected: no output, `exit: 0` (allowed — falls through to normal permission flow).

- [ ] **Step 6: Test `guard-push.sh` — a main-branch push is denied**

```bash
TGT=$(mktemp -d) && mkdir -p "$TGT/.autodev"
jq '.repo.default_branch="main" | .review.delivery="draft_pr"' \
  /Users/svickn/working/autodev/reference/deployment.example.json > "$TGT/.autodev/deployment.json"
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin main\"},\"cwd\":\"$TGT\"}" \
  | /Users/svickn/working/autodev/hooks/guard-push.sh | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
echo "exit: $?"
rm -rf "$TGT"
```

Expected: `exit: 0` (the `jq -e` assertion succeeded — the hook denied it).

- [ ] **Step 7: Test `guard-push.sh` — `local_diff` mode denies even a feature-branch push**

```bash
TGT=$(mktemp -d) && mkdir -p "$TGT/.autodev"
jq '.repo.default_branch="main" | .review.delivery="local_diff"' \
  /Users/svickn/working/autodev/reference/deployment.example.json > "$TGT/.autodev/deployment.json"
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin feature/x\"},\"cwd\":\"$TGT\"}" \
  | /Users/svickn/working/autodev/hooks/guard-push.sh | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
echo "exit: $?"
rm -rf "$TGT"
```

Expected: `exit: 0`.

- [ ] **Step 8: Test `guard-docs.sh` — Edit on AGENTS.md is denied, Edit elsewhere is allowed**

```bash
echo '{"tool_name":"Edit","tool_input":{"file_path":"/repo/AGENTS.md"}}' \
  | /Users/svickn/working/autodev/hooks/guard-docs.sh | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
echo "AGENTS.md exit: $?"

echo '{"tool_name":"Edit","tool_input":{"file_path":"/repo/src/foo.ts"}}' \
  | /Users/svickn/working/autodev/hooks/guard-docs.sh
echo "src/foo.ts exit: $?"
```

Expected: `AGENTS.md exit: 0`; `src/foo.ts exit: 0` with no stdout (falls through, allowed).

- [ ] **Step 9: Test `session-signal.sh` — one line, only when configured**

```bash
TGT=$(mktemp -d) && mkdir -p "$TGT/.autodev/board"
jq '.client_name="ScratchCo" | .tracker.kind="local"' \
  /Users/svickn/working/autodev/reference/deployment.example.json > "$TGT/.autodev/deployment.json"
echo '{}' > "$TGT/.autodev/board/AD-1.json"
echo "{\"cwd\":\"$TGT\"}" | /Users/svickn/working/autodev/hooks/session-signal.sh \
  | jq -e '.hookSpecificOutput.additionalContext | contains("ScratchCo") and contains("1 stories") and (length < 200)'
echo "exit: $?"

UNCONF=$(mktemp -d)
echo "{\"cwd\":\"$UNCONF\"}" | /Users/svickn/working/autodev/hooks/session-signal.sh
echo "unconfigured exit: $?ẞ"
rm -rf "$TGT" "$UNCONF"
```

(Fix the stray character in that last echo before running — it should read `echo "unconfigured exit: $?"`.)

Expected: first `exit: 0`; the unconfigured repo produces no stdout and `unconfigured exit: 0`.

- [ ] **Step 10: Remove the superseded session-init.sh and pre-push.sh from `template/`**

```bash
cd /Users/svickn/working/autodev
git rm template/scripts/session-init.sh template/ops/pre-push.sh
```

- [ ] **Step 11: Commit**

```bash
cd /Users/svickn/working/autodev
git add hooks/hooks.json hooks/session-signal.sh hooks/guard-push.sh hooks/guard-docs.sh
git commit -m "feat(plugin): replace SessionStart manual-injection + .git/hooks/pre-push with plugin hooks

- session-signal.sh: one-line ambient signal instead of injecting the full manual
- guard-push.sh: PreToolUse push guard, replaces .git/hooks/pre-push
- guard-docs.sh: PreToolUse docs guard, replaces the settings.json AGENTS.md/CLAUDE.md deny"
```

---

### Task 17: Rewrite `devloop-tick.sh` (repo-path arg + config-driven allowlist)

The old version had `{{TICK_MIN}}`, `{{RUN_HOME}}`, `{{REPO_PATH}}` baked in by `install.sh` and assumed a pre-approved `settings.json`. The new version takes the repo path as an argument, reads `runner.home_dir` from that repo's own config, and builds a `--allowedTools` list for the headless `claude -p` call instead of relying on any written permissions.

**Files:**
- Create: `scripts/devloop-tick.sh`
- Delete: `template/scripts/devloop-tick.sh` (superseded, not ported — different CLI contract)

**Interfaces:**
- Consumes: `.autodev/deployment.json` (`runner.home_dir`, `commands.*`, `repo.*`, `backup.remote`) from the repo passed as `$1`. Calls `scripts/notify.sh` (Task 18), `scripts/report.mjs` (Task 2), `scripts/tracker.mjs` (Task 2) via `$(dirname "$0")` — all must live in the same directory at runtime (see Global Constraints).
- Produces: invokes `claude -p "/autodev:loop" --allowedTools ...` in the target repo.

- [ ] **Step 1: Write the script**

```bash
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
```

Write this to `scripts/devloop-tick.sh`, then `chmod +x scripts/devloop-tick.sh`.

- [ ] **Step 2: Verify no `{{` remains**

Run: `grep -n '{{' scripts/devloop-tick.sh`
Expected: no output.

- [ ] **Step 3: Smoke-test the allowlist-building logic in isolation (without actually invoking `claude`)**

```bash
TGT=$(mktemp -d) && mkdir -p "$TGT/.autodev"
jq '.commands.test="npm test" | .repo.feature_branch_prefix="feature/" | .repo.story_branch_prefix="autodev"' \
  /Users/svickn/working/autodev/reference/deployment.example.json > "$TGT/.autodev/deployment.json"
bash -n /Users/svickn/working/autodev/scripts/devloop-tick.sh
echo "syntax check: $?"
rm -rf "$TGT"
```

Expected: `syntax check: 0` (this only checks the script parses — a full end-to-end run needs a real `claude` invocation and is exercised manually in Task 23, not in CI).

- [ ] **Step 4: Remove the superseded template version (it's replaced, not ported — the new file has a different CLI contract)**

```bash
cd /Users/svickn/working/autodev
git rm template/scripts/devloop-tick.sh
```

- [ ] **Step 5: Commit**

```bash
cd /Users/svickn/working/autodev
git add scripts/devloop-tick.sh
git commit -m "feat(plugin): rewrite devloop-tick.sh — repo-path arg, config-driven --allowedTools

Removes template/scripts/devloop-tick.sh (superseded, not ported — the old
version had {{RUN_HOME}}/{{REPO_PATH}}/{{TICK_MIN}} baked in by install.sh)."
```

---

### Task 18: Rewrite `notify.sh` and `watchdog.sh` (repo-path arg)

The old `notify.sh` computed its config path from its own script location (`$HERE/../../.autodev/deployment.json`), assuming it was copied two directories under the repo root. That assumption breaks once it lives at a stable per-operator path unrelated to any repo. Both scripts now take `<repo-path>` as their first argument.

**Files:**
- Create: `scripts/notify.sh`
- Create: `scripts/watchdog.sh`
- Delete: `template/scripts/notify.sh`, `template/scripts/watchdog.sh` (superseded, not ported — different CLI contract)

**Interfaces:**
- `notify.sh <repo-path> {limited <epoch>|resumed|stalled <age>}` — calls `tracker.mjs` (Task 2) via `$(dirname "$0")`.
- `watchdog.sh <repo-path>` — calls `notify.sh` (this task) via `$(dirname "$0")`.
- Consumed by: `devloop-tick.sh` (Task 17) calls `notify.sh`; a second launchd entry calls `watchdog.sh` directly (documented in Task 19's `ops/launchd-timer.md`).

- [ ] **Step 1: Write `scripts/notify.sh`**

```bash
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
```

Write this to `scripts/notify.sh`, then `chmod +x scripts/notify.sh`.

- [ ] **Step 2: Write `scripts/watchdog.sh`**

```bash
#!/usr/bin/env bash
# autoDev — dead-man watchdog. Runs on its own timer (e.g. every 15 min), from the
# stable per-operator copy (see ops/launchd-timer.md) — one watchdog instance per
# repo running the timer. If the heartbeat is stale > 60 min AND we're not in a
# known rate-limit pause, the engine has stalled — file a board issue so the team
# sees it where they already look.
#
# Usage: watchdog.sh <repo-path>
set -uo pipefail

REPO="${1:?usage: watchdog.sh <repo-path>}"
CONFIG="$REPO/.autodev/deployment.json"
[[ -f "$CONFIG" ]] || { echo "watchdog: no $CONFIG" >&2; exit 1; }
RUN_HOME="$(jq -r '.runner.home_dir // "~/.autodev"' "$CONFIG")"
RUN_HOME="${RUN_HOME/#\~/$HOME}"
HEARTBEAT="$RUN_HOME/heartbeat"
PAUSE="$RUN_HOME/rate-limited-until"
LOCK="$RUN_HOME/devloop.lock"
STALE_SECONDS=3600
HUNG_SECONDS=2700        # a single tick shouldn't hold the lock this long with no commits

now=$(date +%s)
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo "$now"; }

# A known rate-limit pause is healthy-idle, not a stall.
if [[ -f "$PAUSE" ]]; then
  until=$(cat "$PAUSE" 2>/dev/null || echo 0)
  if [[ "$now" -lt "$until" ]]; then
    exit 0   # paused on purpose; resumes automatically at $until
  fi
fi

# --- hung-tick detection — lock held a long time AND no repo progress ---
if [[ -f "$LOCK" ]]; then
  lockage=$(( now - $(mtime "$LOCK") ))
  if (( lockage > HUNG_SECONDS )); then
    lastcommit=$(git -C "$REPO" log --all -1 --format=%ct 2>/dev/null || echo 0)
    if (( now - lastcommit > HUNG_SECONDS )); then
      pid=$(cat "$LOCK" 2>/dev/null || true)
      [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null || true
      rm -f "$LOCK"
      "$(dirname "$0")/notify.sh" "$REPO" stalled "$lockage"   # hung tick: cleared the wedged lock
    fi
  fi
fi

if [[ ! -f "$HEARTBEAT" ]]; then exit 0; fi   # never started yet
last=$(mtime "$HEARTBEAT")
age=$(( now - last ))

if (( age > STALE_SECONDS )); then
  "$(dirname "$0")/notify.sh" "$REPO" stalled "$age"
  command -v osascript >/dev/null && \
    osascript -e 'display notification "autoDev engine appears stalled" with title "⚠️ ENGINE STALLED"' 2>/dev/null || true
fi
```

Write this to `scripts/watchdog.sh`, then `chmod +x scripts/watchdog.sh`.

- [ ] **Step 3: Verify no `{{` remains in either file**

Run: `grep -n '{{' scripts/notify.sh scripts/watchdog.sh`
Expected: no output.

- [ ] **Step 4: Smoke-test `notify.sh`'s usage error path (no Linear/board needed)**

```bash
bash /Users/svickn/working/autodev/scripts/notify.sh 2>&1
echo "exit: $?"
```

Expected: prints the usage line to stderr, `exit: 1`.

- [ ] **Step 5: Smoke-test `watchdog.sh` against a scratch repo with no heartbeat yet (should no-op)**

```bash
TGT=$(mktemp -d) && mkdir -p "$TGT/.autodev"
RH=$(mktemp -d)
jq --arg rh "$RH" '.runner.home_dir=$rh' /Users/svickn/working/autodev/reference/deployment.example.json > "$TGT/.autodev/deployment.json"
bash /Users/svickn/working/autodev/scripts/watchdog.sh "$TGT"
echo "exit: $?"
rm -rf "$TGT" "$RH"
```

Expected: `exit: 0`, no output (no heartbeat file yet → "never started" no-op path).

- [ ] **Step 6: Remove the superseded template versions (replaced, not ported — different CLI contract)**

```bash
cd /Users/svickn/working/autodev
git rm template/scripts/notify.sh template/scripts/watchdog.sh
```

- [ ] **Step 7: Commit**

```bash
cd /Users/svickn/working/autodev
git add scripts/notify.sh scripts/watchdog.sh
git commit -m "feat(plugin): rewrite notify.sh and watchdog.sh to take <repo-path> instead of a baked-in path

Removes template/scripts/notify.sh and template/scripts/watchdog.sh (superseded,
not ported)."
```

---

### Task 19: Port + rewrite `ops/` — Linear setup doc, launchd template, and a new timer-enable doc

**Files:**
- Move: `template/ops/linear-setup.md` → `ops/linear-setup.md`
- Move: `template/ops/launchd.plist.template` → `ops/launchd.plist.template`
- Create: `ops/launchd-timer.md`

**Interfaces:**
- Referenced by `commands/init.md` (Task 13, step 6) and `reference/manual.md`.

- [ ] **Step 1: Move the two ops files**

```bash
cd /Users/svickn/working/autodev
git mv template/ops/linear-setup.md ops/linear-setup.md
git mv template/ops/launchd.plist.template ops/launchd.plist.template
```

- [ ] **Step 2: De-placeholder `linear-setup.md` — this is read directly now, not rendered**

```bash
cd /Users/svickn/working/autodev
sed -i.bak \
  -e "s|{{CLIENT_NAME}}|<your deployment's client_name>|g" \
  -e "s|{{LINEAR_TEAM}}|<your Linear team name>|g" \
  ops/linear-setup.md
rm -f ops/linear-setup.md.bak
```

- [ ] **Step 3: Verify no `{{` remains in `linear-setup.md`**

Run: `grep -n '{{' ops/linear-setup.md`
Expected: no output.

- [ ] **Step 4: Update the header comment on `launchd.plist.template` (still intentionally templated — see rewritten install instructions below)**

```
Old string:
<!--
  autoDev timer for {{CLIENT_NAME}} (macOS launchd). Phase 3 only — install when
  going 24/7. Install TWO copies: one for the tick, one for the watchdog.

  Install:
    cp this → ~/Library/LaunchAgents/com.autodev.{{CLIENT_NAME}}.tick.plist
    (edit Label + ProgramArguments path; for the watchdog copy, point at
     watchdog.sh and use Label …watchdog)
    launchctl load ~/Library/LaunchAgents/com.autodev.{{CLIENT_NAME}}.tick.plist

  A laptop running this needs to stay awake (lid open + on power, or
  `caffeinate -s`). For true 24/7, run on the always-on host.
-->

New string:
<!--
  autoDev timer template (macOS launchd) — Phase 3 only, install when going 24/7.
  This file is intentionally still a hand-rendered TEMPLATE (unlike the rest of the
  plugin): the 24/7 timer is opt-in and per-operator, so there's no command that
  writes it automatically. See ops/launchd-timer.md for the full walkthrough
  (render both a tick copy and a watchdog copy, substituting {{CLIENT_NAME}},
  {{REPO_PATH}}, {{RUN_HOME}}, {{TICK_SECONDS}}/{{TICK_MIN}} by hand or with the
  one-liner sed command shown there).

  A laptop running this needs to stay awake (lid open + on power, or
  `caffeinate -s`). For true 24/7, run on the always-on host.
-->
```

- [ ] **Step 5: Write `ops/launchd-timer.md`**

```markdown
# 24/7 timer setup (opt-in, per operator machine)

This is the **only** part of autoDev that still involves manually copying files —
by design (see the plugin design spec's "Open questions"): it's opt-in, rarely
used, and `launchd` needs a stable file path that survives a plugin update (the
plugin's own cache directory is versioned and moves on every upgrade).

## 1. Copy the scripts to a stable path

```bash
mkdir -p ~/.autodev/bin
cp "${CLAUDE_PLUGIN_ROOT}/scripts/"{devloop-tick.sh,watchdog.sh,notify.sh,tracker.mjs,linear.mjs,report.mjs} ~/.autodev/bin/
chmod +x ~/.autodev/bin/*.sh
```

All six are copied together (not just the three timer scripts) because
`devloop-tick.sh`/`watchdog.sh`/`notify.sh` call `tracker.mjs`/`linear.mjs`/
`report.mjs` via `$(dirname "$0")` — they need to be siblings at runtime.
Re-run this `cp` after every plugin update to pick up fixes.

## 2. Render the launchd plists

```bash
REPO=/absolute/path/to/the/client/repo
CLIENT=$(jq -r '.client_name' "$REPO/.autodev/deployment.json" | tr '[:upper:] ' '[:lower:]-')
TICK_MIN=$(jq -r '.execution.tick_interval_minutes' "$REPO/.autodev/deployment.json")
RUN_HOME=$(jq -r '.runner.home_dir' "$REPO/.autodev/deployment.json")
RUN_HOME="${RUN_HOME/#\~/$HOME}"

render() { # <program> <label-suffix> -> writes ~/Library/LaunchAgents/com.autodev.$CLIENT.$2.plist
  sed -e "s|{{CLIENT_NAME}}|$CLIENT|g" \
      -e "s|{{REPO_PATH}}/scripts/autodev/devloop-tick.sh|$HOME/.autodev/bin/$1|g" \
      -e "s|{{RUN_HOME}}|$RUN_HOME|g" \
      -e "s|{{TICK_SECONDS}}|$(( TICK_MIN * 60 ))|g" \
      -e "s|{{TICK_MIN}}|$TICK_MIN|g" \
      "${CLAUDE_PLUGIN_ROOT}/ops/launchd.plist.template" \
      > ~/Library/LaunchAgents/com.autodev.$CLIENT.$2.plist
}
render devloop-tick.sh tick
render watchdog.sh watchdog
```

Edit each plist's `ProgramArguments` to add `"$REPO"` as an argument (the template
was written for a version that took no argument — devloop-tick.sh and watchdog.sh
now both require `<repo-path>` as `$1`):

```bash
for f in tick watchdog; do
  plutil -insert ProgramArguments.1 -string "$REPO" ~/Library/LaunchAgents/com.autodev.$CLIENT.$f.plist
done
```

## 3. Load them

```bash
launchctl load ~/Library/LaunchAgents/com.autodev.$CLIENT.tick.plist
launchctl load ~/Library/LaunchAgents/com.autodev.$CLIENT.watchdog.plist
```

The machine needs to stay awake (lid open + on power, or `caffeinate -s`) unless
it's an always-on host.

## To stop

```bash
launchctl unload ~/Library/LaunchAgents/com.autodev.$CLIENT.tick.plist
launchctl unload ~/Library/LaunchAgents/com.autodev.$CLIENT.watchdog.plist
```
```

Write this to `ops/launchd-timer.md`.

- [ ] **Step 6: Commit**

```bash
cd /Users/svickn/working/autodev
git add ops/linear-setup.md ops/launchd.plist.template ops/launchd-timer.md
git commit -m "feat(plugin): port ops/ docs, add launchd-timer.md for the opt-in 24/7 setup"
```

---

### Task 20: Delete the old install-time infrastructure

**Files:**
- Delete: `install.sh`
- Delete: `template/` (should now be empty except leftover empty dirs)
- Delete tracked contents of: `config/` (the example file already moved in Task 12; only the gitignored real per-client configs may remain on disk, untouched)

**Interfaces:** none — pure cleanup, no other task depends on these paths existing.

- [ ] **Step 1: Confirm `template/` is empty of tracked files before deleting**

Run: `git -C /Users/svickn/working/autodev ls-files template/`
Expected: no output (everything under `template/` was moved by Tasks 2–10, 19; `session-init.sh` and `pre-push.sh` were `git rm`'d in Task 16; `devloop-tick.sh`, `notify.sh`, and `watchdog.sh` were `git rm`'d in Tasks 17–18).

- [ ] **Step 2: Delete `install.sh` and the (now-empty) `template/` directory**

```bash
cd /Users/svickn/working/autodev
git rm install.sh
rmdir template/.claude/skills template/.claude/commands template/.claude template/scripts template/ops template 2>/dev/null || true
```

- [ ] **Step 3: Confirm `config/` has no tracked files left besides what Task 12 already moved**

Run: `git -C /Users/svickn/working/autodev ls-files config/`
Expected: no output.

```bash
cd /Users/svickn/working/autodev
rmdir config 2>/dev/null || echo "config/ left in place (still has gitignored local files — that's fine, it's gitignored)"
```

- [ ] **Step 4: Verify the working tree has no leftover `{{` outside the one intentional template**

Run: `grep -rl '{{' --include='*.md' --include='*.sh' --include='*.json' commands/ reference/ hooks/ scripts/ 2>/dev/null`
Expected: no output.

Run: `grep -l '{{' ops/*.template 2>/dev/null`
Expected: `ops/launchd.plist.template` (the one deliberate exception).

- [ ] **Step 5: Commit**

```bash
cd /Users/svickn/working/autodev
git add -A
git commit -m "chore(plugin): remove install.sh and the template/ render tree — nothing left to render"
```

---

### Task 21: Update `README.md`

**Files:**
- Modify: `README.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Replace the "What you get" file tree**

```
Old string:
## What you get

```
autoDev/
├── config/deployment.example.json   # per-client config — copy + fill in
├── install.sh                       # render the engine in + auto-create the Linear board
├── BACKLOG.md                       # roadmap + run-gap audit (what's shipped / planned)
├── template/
│   ├── .claude/
│   │   ├── autodev.md               # engine manual (concierge + rulebook + toggles) — NOT your CLAUDE.md; loaded via the SessionStart hook
│   │   ├── settings.json            # allowlisted permissions + SessionStart hook (bot can't merge to main; can't edit your AGENTS.md/CLAUDE.md)
│   │   ├── commands/devloop.md      # the /devloop SLASH command (heartbeat entry)
│   │   └── skills/
│   │       ├── intake.md            # plain-English front door · feature-vs-bug gate · cli|linear · attaches wireframes
│   │       ├── prd.md               # PRD (BrainGrid preferred · agent fallback) → Gate 1
│   │       ├── breakdown.md         # → Project · Milestones · Issues (full BrainGrid spec copied in)
│   │       ├── devloop.md           # one heartbeat: dev → QA → merge · live board moves + comment logging
│   │       ├── merge-verify.md      # acceptance QA + post-merge clean-room + report + prod sign-off
│   │       └── _story-template.md   # the story contract
│   ├── scripts/
│   │   ├── session-init.sh          # SessionStart hook — re-orients every session so autoDev (not ad-hoc CC) drives
│   │   ├── detect-conventions.sh    # scans the target repo → .autodev/conventions.md (use generated types · the theme · reuse)
│   │   ├── check-docs.sh            # first-install scan: flags rules in your AGENTS.md/CLAUDE.md that fight the workflow
│   │   ├── tracker.mjs              # THE board facade (move/comment/…/board/flush-mirror) — local git-native board or Linear
│   │   ├── linear.mjs               # the Linear driver behind tracker.mjs (kind=linear / mirror)
│   │   ├── report.mjs               # periodic operator digest (reporting.cadence)
│   │   ├── doctor.sh                # preflight: tools · toolchain · token · config ids · hermetic safety · visual-QA driver · docs conflicts
│   │   ├── devloop-tick.sh          # timer entry: portable lock + rate-limit gate + tick + digest
│   │   ├── watchdog.sh              # dead-man alarm + hung-tick recovery → Linear
│   │   └── notify.sh                # rate-limit pause/resume → Linear
│   └── ops/{launchd.plist.template, linear-setup.md}
└── docs/
```

New string:
## What you get

autoDev ships as a **Claude Code plugin** — nothing is copied into your repo.
Enabling it adds three commands and a couple of guardrail hooks; everything else
(the engine manual, the per-stage playbooks, the scripts) lives inside the plugin
package and is read at runtime via `${CLAUDE_PLUGIN_ROOT}`.

```
autodev/                              (the plugin package)
├── .claude-plugin/plugin.json        # plugin manifest
├── commands/
│   ├── init.md                       # /autodev:init  — guided one-time setup, writes .autodev/deployment.json
│   ├── new.md                        # /autodev:new   — the only way work enters the engine
│   └── loop.md                       # /autodev:loop  — advance one bounded step (PRD → breakdown → dev/QA → merge-verify)
├── reference/                        # playbooks — read explicitly by the commands above; never auto-triggered
│   ├── manual.md                     # engine manual: concierge routing, non-negotiables, toggles
│   ├── intake.md · prd.md · breakdown.md · devloop.md · merge-verify.md · story-template.md
│   └── deployment.example.json       # the full config schema, used by /autodev:init
├── scripts/                          # tracker.mjs · linear.mjs · report.mjs · doctor.sh · detect-conventions.sh ·
│                                      # check-docs.sh · devloop-tick.sh · watchdog.sh · notify.sh
├── hooks/hooks.json                  # a one-line SessionStart signal + two PreToolUse guardrails (push, docs) — no settings.json write, ever
├── ops/{linear-setup.md, launchd-timer.md, launchd.plist.template}
├── BACKLOG.md
└── docs/
```

In a client repo, the **entire footprint** is `.autodev/deployment.json` plus
runtime state created lazily on first use (`.autodev/board/`, `conventions.md`,
`metrics.jsonl`, `logs/`). Nothing under `.claude/` is ever written.
```

- [ ] **Step 2: Replace the "Deploy to a new client" section**

```
Old string:
## Deploy to a new client (rinse and repeat)

```bash
./install.sh --init            # guided: detects branch/commands from the repo, asks ~5
                               # questions, defaults to the zero-setup LOCAL board,
                               # writes config/<name>.json, offers to install
# (manual alternative:)
cp config/deployment.example.json config/<client>.json   # fill: repo, branch, commands…
./install.sh config/<client>.json                        # renders the engine (+ board setup per tracker.kind)
./install.sh --all                                       # re-render EVERY deployment (fleet upgrade)
# (if client_name is still unset/placeholder, install prompts for it and saves it back;
#  set AUTODEV_NONINTERACTIVE=1 to skip the prompt in CI/managed installs)
scripts/autodev/doctor.sh                                 # preflight — fix any ✗ before running
# IMPORTANT: start a Claude Code session IN this repo (if you're already in Claude Code,
#   just open this repo as the workspace / start a new session) and ACCEPT the one-time
#   trust+hook prompt — that activates the SessionStart hook that makes autoDev drive.
#   (install.sh prints the exact step for your situation.)
# then: wire BrainGrid (optional — see below) · connect Linear MCP · bot identity + branch protection
```

The engine is **client-agnostic**; everything per-client lives in the one config.

New string:
## Set up a new repo (rinse and repeat)

```bash
# in Claude Code, with the autodev plugin enabled and this repo as the workspace:
/autodev:init      # guided: detects branch/commands from the repo, asks ~5 questions,
                    # defaults to the zero-setup LOCAL board, writes .autodev/deployment.json
/autodev:new        # capture the first piece of work
/autodev:loop        # advance it — re-run any time; nothing runs on its own between calls
```

No file copying, no session-restart dance, no trust/hook prompt beyond the plugin's
own one-time enable. `.autodev/deployment.json` is the entire per-repo footprint;
everything else the engine needs — the manual, the playbooks, the scripts — lives
in the plugin and updates automatically when the plugin updates. BrainGrid,
Linear, and branch-protection wiring are still manual, auth-bound steps —
`/autodev:init` prints exactly what's left to do.
```

- [ ] **Step 3: Fix the "non-negotiables" bullet about the SessionStart hook**

```
Old string:
- **autoDev drives, not ad-hoc Claude Code — but it stays in its own files.** The engine
  manual lives at **`.claude/autodev.md`** (never your `CLAUDE.md`), is **authoritative for
  the WORKFLOW**, and is injected every session by a **`SessionStart` hook** (deterministic,
  harness-executed). **Your `AGENTS.md` / `CLAUDE.md` stay the authority on coding
  conventions** — autoDev reads and obeys them and is **denied from editing them**; a
  convention change comes as a separate PR with rationale, never a silent in-place edit.
  One-time: accept the workspace-trust prompt so the hook runs.

New string:
- **autoDev only drives when you tell it to — and stays in its own files.** Nothing runs
  from plain conversation; only **`/autodev:init`**, **`/autodev:new`**, and
  **`/autodev:loop`** do anything. The engine manual lives in the plugin's
  **`reference/manual.md`** (never your `CLAUDE.md`) and is read explicitly by those
  three commands — a one-line `SessionStart` hook is the only ambient behavior, and it
  just tells you the commands exist. **Your `AGENTS.md` / `CLAUDE.md` stay the authority
  on coding conventions** — autoDev reads and obeys them, and a `PreToolUse` hook denies
  any Edit/Write to them; a convention change comes as a separate PR with rationale,
  never a silent in-place edit.
```

- [ ] **Step 4: Verify the README no longer references `install.sh`, `template/`, or `scripts/autodev/`**

Run: `grep -n 'install\.sh\|template/\|scripts/autodev' README.md`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
cd /Users/svickn/working/autodev
git add README.md
git commit -m "docs: update README for the plugin distribution model"
```

---

### Task 22: Rewrite `tests/smoke.sh`

The old smoke test drove `install.sh` end-to-end. There's no more `install.sh` — the equivalent bootstrap is a Claude Code slash command (`/autodev:init`), which a shell script can't invoke directly. This rewrite instead exercises every deterministic, script-level contract directly (the same philosophy the old smoke test already used for `tracker.mjs`/`check-docs.sh`/`detect-conventions.sh` — it never tested the *prose* of the skill files either, only the code around them).

**Files:**
- Modify: `tests/smoke.sh`

**Interfaces:** none — this is the test entry point itself.

- [ ] **Step 1: Rewrite the file**

```bash
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

echo "session-signal hook (one line, only when configured):"
check "emits a short line naming both commands" bash -c \
  "echo '{\"cwd\":\"$TGT\"}' | '$PLUGIN/hooks/session-signal.sh' | jq -e '.hookSpecificOutput.additionalContext | contains(\"/autodev:loop\") and contains(\"/autodev:new\") and (length < 200)'"
UNCONF=$(mktemp -d)
check "silent when unconfigured" bash -c \
  "test -z \"\$(echo '{\"cwd\":\"$UNCONF\"}' | '$PLUGIN/hooks/session-signal.sh')\""
rmdir "$UNCONF"

echo "push guard (PreToolUse — replaces .git/hooks/pre-push):"
check "feature branch push allowed" bash -c \
  "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin feature/x\"},\"cwd\":\"$TGT\"}' | '$PLUGIN/hooks/guard-push.sh' | wc -c | grep -qx 0"
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
  "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TGT/src/foo.ts\"}}' | '$PLUGIN/hooks/guard-docs.sh' | wc -c | grep -qx 0"

echo "local tracker (git-native board):"
TRK="$PLUGIN/scripts/tracker.mjs"
LID=$(cd "$TGT" && node "$TRK" create-issue --title "Smoke story" --stage ready_for_ai_dev --labels ai-eligible 2>/dev/null)
check "create-issue returns an id" test -n "$LID"
check "move + note" bash -c "cd '$TGT' && node '$TRK' move '$LID' ai_development --note 'dev started' | grep -q 'AI Development'"
check "comment" bash -c "cd '$TGT' && node '$TRK' comment '$LID' 'progress'"
check "history recorded in issue file" bash -c "jq -e '.history | length >= 2' '$TGT/.autodev/board/$LID.json'"
check "board renders html" bash -c "cd '$TGT' && node '$TRK' board >/dev/null && test -f '$TGT/.autodev/board.html'"
check "tracker doctor ok" bash -c "cd '$TGT' && node '$TRK' doctor | grep -q 'local board'"

echo
if [[ $FAIL -eq 0 ]]; then echo "smoke: PASS"; else echo "smoke: FAIL"; fi
exit $FAIL
```

Write this to `tests/smoke.sh`, then `chmod +x tests/smoke.sh`.

- [ ] **Step 2: Run it**

Run: `bash /Users/svickn/working/autodev/tests/smoke.sh`
Expected: every line prefixed ✓, ending in `smoke: PASS` and exit code 0.

- [ ] **Step 3: If anything fails, fix the underlying script/hook (not the test) and re-run until green**

This step has no fixed content — it's the debug loop. Do not weaken an assertion to make it pass; the assertions above encode real regressions from past runs (see the original `tests/smoke.sh` history — same discipline applies).

- [ ] **Step 4: Commit**

```bash
cd /Users/svickn/working/autodev
git add tests/smoke.sh
git commit -m "test: rewrite smoke.sh to exercise the plugin's scripts/hooks directly (no more install.sh)"
```

---

### Task 23: End-to-end manual verification with a real Claude Code session

`tests/smoke.sh` (Task 22) covers every deterministic script/hook. This task is the one piece that needs an actual Claude Code session, since the three commands are prose interpreted at runtime — per the repo's own testing conventions (see `docs/superpowers/plans/` guidance to use the `verify` skill for runtime behavior on product changes with a real surface to exercise), confirm the plugin loads and behaves as designed before calling this done.

**Files:** none — verification only.

**Interfaces:** none.

- [ ] **Step 1: Load the plugin locally in a scratch repo**

```bash
SCRATCH=$(mktemp -d) && git -C "$SCRATCH" init -q
echo '{"scripts":{"test":"echo ok"}}' > "$SCRATCH/package.json"
cd "$SCRATCH"
claude --plugin-dir /Users/svickn/working/autodev
```

- [ ] **Step 2: In that session, confirm the ambient signal is silent (no `.autodev/deployment.json` yet)**

Expected: the session starts with no autoDev-related context injected — ask "what plugins are active?" or just observe the greeting is plain, not autoDev's.

- [ ] **Step 3: Run `/autodev:init`, answer the prompts, confirm only `.autodev/` is written**

Run inside the session: `/autodev:init`
After it completes, from a separate terminal: `find "$SCRATCH" -newer "$SCRATCH/package.json" -not -path '*/.git/*'`
Expected: only paths under `$SCRATCH/.autodev/` appear — nothing under `.claude/`.

- [ ] **Step 3b: Re-run `/autodev:init` in the same repo and confirm it reconfigures rather than corrupts**

Run inside the session (same repo, same session or a fresh one): `/autodev:init`
Expected: it opens by noting `.autodev/deployment.json` already exists and summarizes
the current settings (per `commands/init.md` step 1) rather than treating this as a
first-time setup; `.autodev/deployment.json` remains valid JSON afterward
(`jq . "$SCRATCH/.autodev/deployment.json"` from a separate terminal succeeds).

- [ ] **Step 4: Start a new session in the same repo and confirm the one-line signal now appears**

```bash
cd "$SCRATCH" && claude --plugin-dir /Users/svickn/working/autodev
```

Expected: a single short line mentioning `/autodev:loop` / `/autodev:new` appears at session start — not the full manual, not a forced greeting-as-Marj monologue.

- [ ] **Step 5: Confirm plain conversation does NOT trigger intake**

In that session, say something like "we should add a login page" **without** running `/autodev:new`.
Expected: Claude responds as a normal assistant (or references that `/autodev:new` exists) — it does **not** start an intake interview, create a board issue, or otherwise act as the engine.

- [ ] **Step 6: Run `/autodev:new` with that same request and confirm intake actually runs**

Run: `/autodev:new we should add a login page`
Expected: an intake interview begins per `reference/intake.md` (asks for problem/solution/users/priority/timeline, or notes what's already covered).

- [ ] **Step 7: Confirm the push guard fires for real inside the session**

Ask Claude to run `git push origin main` via Bash (it will refuse/attempt and the hook should deny it before execution).
Expected: the tool call is denied with the `guard-push.sh` reason text, not a normal permission prompt.

- [ ] **Step 8: Exit the session and run one real headless tick (the one thing `tests/smoke.sh` can't cover — it needs an actual `claude` invocation)**

```bash
mkdir -p "$SCRATCH/.autodev"   # already exists from step 3, but harmless if re-run
RUN_HOME=$(mktemp -d)
jq --arg rh "$RUN_HOME" '.runner.home_dir=$rh' "$SCRATCH/.autodev/deployment.json" > "$SCRATCH/.autodev/t" \
  && mv "$SCRATCH/.autodev/t" "$SCRATCH/.autodev/deployment.json"
bash /Users/svickn/working/autodev/scripts/devloop-tick.sh "$SCRATCH"
echo "exit: $?"
cat "$RUN_HOME"/logs/*.jsonl 2>/dev/null | tail -1
```

Expected: `exit: 0`; the tick ran `claude -p "/autodev:loop" --allowedTools ...`
without hitting a permission prompt (there's no terminal attached to answer one, so
a prompt would hang or fail the run — a clean exit confirms the `--allowedTools`
list was sufficient); the JSONL log has one line for this tick.

```bash
rm -rf "$RUN_HOME"
```

- [ ] **Step 9: Clean up**

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 10: If every check above passed, the migration is verified — no code change in this step, just the go/no-go gate before considering the plan complete.**

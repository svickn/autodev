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
6. Run `${CLAUDE_PLUGIN_ROOT}/scripts/write-identity-pointer.sh` from the repo root.
   This writes (or refreshes) a small identity pointer at `.claude/CLAUDE.md` so a
   session that hasn't granted workspace trust yet — and so never runs the
   SessionStart hook — still learns the engine identity, since `CLAUDE.md` auto-loads
   as memory regardless of hook trust. It never touches a team-authored file in that
   slot; it only writes an empty slot or replaces its own prior pointer.
7. Print the manual next-steps report — nothing here is automated, all of it needs
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
8. Run `${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh` from the repo root and show the
   operator anything it flags with a ✗.
9. Confirm: "`.autodev/deployment.json` is ready. Run `/autodev:new` to capture the
   first piece of work, or `/autodev:loop` once stories are queued."

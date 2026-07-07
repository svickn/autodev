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

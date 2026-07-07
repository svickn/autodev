# autoDev → Claude Code plugin conversion — design

## Motivation

autoDev today is a "renderer": `install.sh` reads a per-client JSON config
(`config/<client>.json`, gitignored, living in this engine repo) and copies
~20 files from `template/` into a target client repo — `.claude/autodev.md`,
`.claude/skills/*`, `.claude/settings.json` (overwriting/backing up any
existing one), `scripts/autodev/*`, `.autodev/ops/*` — plus installs a
`.git/hooks/pre-push` guard. Re-deploying to a client means re-running
`install.sh`; fleet-wide upgrades mean `install.sh --all`.

Two problems with this shape once autoDev becomes a Claude Code plugin:

1. **Footprint.** Every client repo accumulates a full copy of the engine's
   code, and installation silently overwrites `.claude/settings.json`
   (hooks + permissions) and `.git/hooks/pre-push`.
2. **Hijacking.** The installed `SessionStart` hook injects the entire
   engine manual + conventions into *every* Claude Code session opened in
   that repo, and the workflow skills (`intake`, `prd`, `breakdown`,
   `merge-verify`) carry broad auto-matching descriptions ("use whenever the
   operator wants to add a feature... e.g. 'we need to add X'"), so casual
   conversation can trigger the PM workflow. There's no way to have autoDev
   installed but dormant.

Claude Code plugins ship skills/commands/agents/hooks/scripts inside the
plugin package itself, addressable via `${CLAUDE_PLUGIN_ROOT}` — nothing
needs to be copied into a target repo for those to work. This design uses
that to eliminate the render step and make activation fully opt-in.

## Goals

- Nothing under a client repo's `.claude/` directory is ever written by
  autoDev.
- autoDev does nothing in a session unless explicitly invoked by command —
  no ambient auto-matching skills, no full-manual injection on session
  start.
- Standing up a new client repo requires no more than answering a short
  wizard once.
- Scheduled/headless 24/7 operation still works without hand-editing
  permissions into the target repo.
- Updating the plugin updates behavior across every repo on next
  invocation — no per-repo re-render step.

## Non-goals

- Changing the underlying workflow (PM → dev → QA → human gates, the board
  state machine, hermetic QA, etc.) — this is a packaging/distribution
  change, not a behavior change.
- Multi-client central config registry. Config is per-repo (decided:
  simpler than preserving the current single-operator fleet-config
  directory; revisit only if actually needed later).
- Auto-discovering/registering `prd`/`breakdown`/`devloop`/`merge-verify`
  as separately invokable skills — they become internal reference docs
  driven by `/autodev:loop`.

## Plugin package layout

The engine repo becomes the plugin itself:

```
autodev/
├── .claude-plugin/
│   └── plugin.json              # manifest: name "autodev", version, etc.
├── commands/
│   ├── init.md                  # /autodev:init
│   ├── new.md                   # /autodev:new
│   └── loop.md                  # /autodev:loop
├── reference/                   # plain docs, NO auto-match frontmatter —
│   │                             # read explicitly by path from commands/*
│   ├── manual.md                # the former autodev.md (non-negotiables, toggles)
│   ├── prd.md
│   ├── breakdown.md
│   ├── devloop.md
│   ├── merge-verify.md
│   └── story-template.md
├── scripts/                     # invoked via ${CLAUDE_PLUGIN_ROOT}/scripts/*
│   ├── tracker.mjs              # board facade (local + Linear)
│   ├── linear.mjs
│   ├── report.mjs
│   ├── doctor.sh
│   ├── detect-conventions.sh
│   ├── check-docs.sh
│   ├── devloop-tick.sh          # timer entry (operator-machine install, see below)
│   ├── watchdog.sh
│   └── notify.sh
├── hooks/
│   └── hooks.json               # SessionStart (ambient signal) + PreToolUse (push guard)
├── ops/
│   ├── linear-setup.md          # referenced by path, never copied
│   └── launchd.plist.template
├── BACKLOG.md
├── README.md
└── LICENSE
```

`install.sh`, `template/`, and the central `config/*.json` directory are
deleted — nothing left to render.

## Command surface

Three discoverable entry points (namespaced `/autodev:*` by the plugin
manifest name). Nothing else in the plugin auto-fires from conversation.

- **`/autodev:init`** — guided setup, replaces `install.sh --init`. Detects
  branch/package-manager/commands from the current repo, asks the same
  handful of questions (tracker kind, mode, assistant name, etc.), and
  writes `.autodev/deployment.json` **into the current repo**. Prints the
  same auth-bound manual steps (BrainGrid, Linear token, branch protection)
  the old install report did. Idempotent — re-running lets you reconfigure.

- **`/autodev:new`** — the front door for new work (feature/bug capture,
  interview, PRD kickoff). Reads `reference/manual.md` +
  `reference/prd.md`-adjacent intake logic explicitly, then proceeds.

- **`/autodev:loop`** — the umbrella router. Reads `.autodev/deployment.json`
  + board/git state, decides what stage is next (PRD drafting → breakdown →
  devloop heartbeat → merge-verify), reads the corresponding
  `reference/*.md` playbook by path, and executes one bounded pass. This is
  what a human runs manually to advance work, and what the timer calls
  headlessly (`claude -p "/autodev:loop"`).

Both `loop` and `new` open by checking whether
`.autodev/deployment.json` exists; if not, they run the same init flow as
`/autodev:init` before doing their normal job. So a brand-new repo can
start from either `/autodev:new` (typical) or `/autodev:loop` (also
fine) without knowing `/autodev:init` exists — but it also stays available
as an explicit, re-runnable step.

## Activation — no hijack

`hooks/hooks.json` (shipped in the plugin, so it never touches the target
repo's own `settings.json`) registers a lightweight `SessionStart` hook:

- Checks for `.autodev/deployment.json` in the repo root.
- If absent: does nothing.
- If present: emits **one line** to context — e.g. "autoDev is configured
  here (N stories in flight) — `/autodev:loop` to continue." — no manual
  injection, no conventions dump, no forced workflow.

This replaces `session-init.sh` (deleted) and is the "minimal ambient
signal" tier: enough that a returning operator remembers autoDev is live in
this repo, nothing that changes how an unrelated Claude Code session
behaves.

`prd`, `breakdown`, `devloop`, `merge-verify` are **not** skills with
auto-match `description` frontmatter anymore — they're plain markdown under
`reference/`, loaded only when a command's own instructions say "read
`${CLAUDE_PLUGIN_ROOT}/reference/prd.md` and follow it," mirroring how the
current `commands/devloop.md` already reads `.claude/autodev.md` and
`.claude/skills/devloop.md` explicitly. This is what actually kills the
"casual mention triggers the PM workflow" problem — the old broad
descriptions are gone, not just narrowed.

## Per-repo footprint

Only two categories of file ever exist in a client repo, both under
`.autodev/` — nothing under `.claude/`:

- **Config**: `.autodev/deployment.json`, written once by `/autodev:init`
  and read by every command thereafter (tracker settings, commands.*,
  personas, review/delivery mode, hermetic QA overrides, bot identity,
  merge policy — same schema as today's `deployment.json`, just located in
  the client repo instead of copied there from a render).
- **Runtime state**, created lazily on first use, never pre-installed:
  `.autodev/conventions.md` (cache, regenerated on demand via
  `scripts/detect-conventions.sh`), `.autodev/board/*` (only if
  `tracker.kind=local`), `.autodev/metrics.jsonl`, `.autodev/logs/`.

## Permissions — interactive vs. headless

Plugin `settings.json` only supports `agent`/`subagentStatusLine` — it
cannot ship a permissions allow-list that auto-applies to a project, so
this is not solved by "put it in the plugin" the way hooks/commands are.

- **Interactive `/autodev:loop` or `/autodev:new`**: a human is present,
  so normal Claude Code permission prompts apply. No pre-grant needed or
  written anywhere.
- **Headless timer ticks**: `devloop-tick.sh` builds an `--allowedTools`
  list from `.autodev/deployment.json` (`commands.install/test/lint/build`,
  scoped git push patterns, `mcp__linear__*`, etc. — the same set the old
  `settings.json` template hard-coded) and invokes
  `claude -p "/autodev:loop" --allowedTools "..."` directly. The allow-list
  lives only in that invocation, never written to the repo.

This fully removes the `.claude/settings.json` write from the install path
— permissions are either handled live (human present) or passed as CLI
flags (headless), never persisted into the target repo.

## Push guard

`.git/hooks/pre-push` is no longer installed. Instead, `hooks/hooks.json`
registers a `PreToolUse` hook matching `Bash` calls shaped like
`git push origin <default-branch>` / `git push <backup-remote>
<default-branch>` and blocks them — same guarantee (bot can't push straight
to the default branch), enforced the same way branch-scoped `Bash` deny
patterns already were, but as a plugin-shipped hook instead of a file
written into `.git/hooks/`. The repo's own git configuration is never
touched. (Caveat, same as today's Claude-Code-permission-deny layer: this
only guards pushes made *through* Claude Code, not a stray manual push from
a human's own terminal — branch protection on the remote is still the real
backstop, same as today.)

## Headless/24-7 timer execution (opt-in, operator-machine-level)

Unchanged in spirit from today's Phase-3 timer, relocated:

- `devloop-tick.sh`, `watchdog.sh`, `notify.sh` are plugin scripts, but
  `launchd` needs a stable file path to invoke on schedule, and plugin
  cache directories are versioned (`.../autodev/1.4.0/...`) and shift on
  update — a plist pointing directly into the plugin cache would silently
  break on the next plugin upgrade.
- So: only if/when an operator opts into the 24/7 timer,
  `/autodev:init` (or a future `/autodev:timer` step — see Open
  Questions) copies just those three scripts to a stable **per-operator**
  location, `~/.autodev/bin/`, and renders the `launchd.plist` to point
  there, same as `ops/launchd.plist.template` does today.
- This is per-operator-machine state, not per-repo — it never appears in
  any client repo, and a typical `/autodev:loop`-only user never triggers
  it.

## Data flow — three walkthroughs

**First run in a fresh repo (`/autodev:new`, no config yet):**
`.autodev/deployment.json` missing → run init wizard inline → detect
branch/package manager → ask ~5 questions → write config → proceed to the
normal intake interview → create the feature-request issue on the board.

**Manual advance (`/autodev:loop`, config exists):**
Read `.autodev/deployment.json` → reconcile board state → determine stage
(PRD review pending? breakdown pending? stories ready for dev? a merge just
happened and needs verify?) → read the matching `reference/*.md` playbook
→ do one bounded unit of work → write results back to the board + git →
exit.

**Headless timer tick:**
`launchd` fires `~/.autodev/bin/devloop-tick.sh <repo-path>` on interval →
script reads `<repo-path>/.autodev/deployment.json` → acquires lock, checks
rate-limit file → builds `--allowedTools` from config → runs
`claude -p "/autodev:loop" --allowedTools "..." -C <repo-path>` → tick
completes → digest/report per `reporting.cadence` → exits. No Claude Code
session is left running; no hook fires beyond the one-line ambient signal
(irrelevant here since `-p` mode has no interactive context to show it in).

## Error handling / edge cases

- **`/autodev:loop` or `/autodev:new` in a repo with a stale/invalid
  `.autodev/deployment.json`** (e.g. hand-edited into invalid JSON): fail
  fast with a clear error pointing at the file, do not silently fall back
  to re-running init over it (would clobber intentional settings).
- **A repo already has a `.git/hooks/pre-push` from something else**: since
  we no longer install a git hook at all, there's nothing to chain/back up
  — simplifies this case away entirely versus today's chain-and-warn
  behavior.
- **Plugin updated mid-flight while a headless tick is running**: the tick
  already resolved `${CLAUDE_PLUGIN_ROOT}` at invocation time (or, for the
  three copied timer scripts, is running from the stable
  `~/.autodev/bin/` copy), so an in-flight tick isn't affected; the next
  tick picks up the new version.
- **Multiple client repos on one machine**: each has its own independent
  `.autodev/deployment.json`; the plugin itself is installed once and
  shared. No cross-repo state.

## Migration plan

1. Restructure this repo into the plugin layout above (`.claude-plugin/`,
   `commands/`, `reference/`, `scripts/`, `hooks/`, `ops/`).
2. Port `template/.claude/autodev.md` → `reference/manual.md`; strip
   `{{PLACEHOLDER}}` tokens (no longer templated — commands read
   `.autodev/deployment.json` directly at runtime instead of values being
   baked in at install time).
3. Port each `template/.claude/skills/*.md` → `reference/*.md`, dropping
   the auto-match `description` frontmatter.
4. Write the three `commands/*.md` (`init`, `new`, `loop`), each opening
   with the "read the manual, check for config, bootstrap if missing"
   preamble.
5. Write `hooks/hooks.json` (ambient SessionStart signal + PreToolUse push
   guard).
6. Port `template/scripts/*` → `scripts/*` with paths updated to read
   `.autodev/deployment.json` from the invoking repo (`$CLAUDE_PROJECT_DIR`
   or an explicit repo-path argument) instead of assuming they were copied
   into that repo.
7. Delete `install.sh`, `template/`, `config/` (keep
   `config/deployment.example.json` → move to
   `reference/deployment.example.json` as the schema reference for
   `/autodev:init` and for anyone hand-editing their config).
8. Update `README.md` for the new install path (`/plugin marketplace add
   ...` + `/autodev:init`) and delete the "Deploy to a new client" /
   `install.sh --all` fleet section.
9. `tests/smoke.sh` gets rewritten to exercise the plugin commands against
   a scratch repo instead of running `install.sh`.

## Testing / verification plan

- `claude --plugin-dir ./autodev` in a scratch git repo; run `/autodev:init`
  end-to-end, confirm only `.autodev/deployment.json` is written (nothing
  under `.claude/`, nothing under `.git/hooks/`).
- Confirm a plain "we should add X" conversation in that same session does
  **not** trigger intake/PRD behavior — only `/autodev:new` does.
- Confirm the SessionStart hook prints the one-line signal (config
  present) and nothing at all in a repo with no `.autodev/deployment.json`.
- Simulate a `git push origin main` via the Bash tool and confirm the
  `PreToolUse` hook blocks it; confirm a feature-branch push is unaffected.
- Run `devloop-tick.sh` against a scratch repo standalone (no interactive
  session) and confirm it completes without any permission prompt, purely
  via `--allowedTools`.
- Re-run `/autodev:init` a second time in the same repo and confirm it's
  treated as reconfiguration, not corruption (idempotent, like `install.sh`
  today).

## Open questions

- Command names are now settled: `init` / `new` / `loop`.
- Whether `/autodev:init` should have an explicit "enable the 24/7 timer"
  sub-step/prompt, or whether that stays a separate manual step documented
  in `ops/` (leaning: keep it a separate, clearly-optional step so
  `/autodev:init` doesn't imply everyone needs the timer).
- Whether `reference/deployment.example.json` should be regenerated/
  trimmed now that per-client Linear board setup is still manual — out of
  scope for this design, revisit during implementation.

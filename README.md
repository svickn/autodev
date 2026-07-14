# autoDev — describe work in plain English; get QA'd, human-reviewed code

autoDev is a [Claude Code](https://claude.com/claude-code) plugin that runs a
PM → dev team → QA pipeline on your repo. You describe what you want; it writes the
spec, breaks it into tickets on a board you can watch, builds each one, QA's its own
work from three angles, and hands you the result for review. **You stay in charge at
exactly two moments:** you approve the plan before anything is built (Gate 1), and
you approve the result before anything ships (Gate 2). Only humans merge.

> **Validated end-to-end** in a sandbox (a 15-story landing page built autonomously,
> 144 unit + 24 e2e tests green) **and hardened by a 20-hour autonomous production
> run** — the gaps that surfaced are folded back in (see [`BACKLOG.md`](./BACKLOG.md)).
>
> **Open source (Apache-2.0).** Free to self-host. **Managed hosting + onboarding
> available** — see [Managed service](#managed-service).

## Your first 30 minutes

You need: Claude Code (logged in with a claude.ai subscription), plus `git`, `node`
18+, and `jq` installed. That's it — if you already use Claude Code, you likely have
all four.

**1 · Install the plugin** — in Claude Code, once per machine:

```
/plugin marketplace add eschnei/autodev
/plugin install autodev@autodev-marketplace
```

**2 · Set up your repo** — open Claude Code *in the repo you want it to work on*:

```
/autodev:init
```

A guided setup: it detects what it can (your branch, your test command) and walks
you through roughly a dozen quick questions, each pre-filled with a sensible
default — pressing Enter accepts. Two matter most: **hands-on vs autopilot** (review
every ticket, or only the plan and the finished feature — start hands-on) and the
**board** (default is a zero-setup local board; Linear is optional, later). It ends
by running a preflight (`doctor`) that flags anything missing, with the fix for each.

**3 · Give it work** — still in Claude Code:

```
/autodev:new
```

Describe the feature like you'd brief a colleague: *"I want a waitlist page for the
beta."* It interviews you — problem, users, priority — and captures the request as a
ticket.

**4 · Let it run:**

```
/autodev:loop
```

Each call advances the work by one step. **The first loop drafts the spec (a PRD —
product requirements document) and then stops, waiting for you.** That pause is
Gate 1 — nothing gets built until you've read the summary it posts and said
**"approved"** (or told it what to change). After you approve, keep running
`/autodev:loop` — it breaks the spec into tickets and builds them one by one. Watch
the board anytime: cards move across columns live (`.autodev/board.html`, or ask
"what's the status?").

**5 · Review the result (Gate 2).** In hands-on mode each finished ticket arrives as
a GitHub draft PR with the QA reports and a manual test script attached. In autopilot
you're called back once, at the end, with the feature **already running** — a URL
plus a checklist ("do X → expect Y"). Click through it like a customer. Say
"approved" (or what's broken), and merge on GitHub when you're happy.

From then on you don't need to remember commands: a configured repo greets you by
name (the assistant is called **Marj** — rename her in config) with a status
snapshot, and plain English drives everything — "here's the PRD", "grab AD-12",
"can you reproduce this bug?". The slash commands remain as shortcuts.

**Pace and cost:** nothing runs between your `/autodev:loop` calls — no daemon, no
background work — unless you deliberately wire the optional 24/7 timer
(`ops/launchd-timer.md`). It runs on your existing Claude subscription; a feature is
many agent-hours of work, so expect it to use meaningful quota. You control spend by
how often you run the loop.

## What it does — and never does — to your machine

Installing a plugin whose hooks are "active in every repo" deserves a straight
answer about what that means:

- **In repos you never configure, autoDev does nothing.** The session hook and the
  push guard both check for `.autodev/deployment.json` and exit silently when it's
  absent. No greeting, no behavior change, no files written.
- **One exception, by design:** in any repo, a guard blocks *Claude Code* from
  editing `AGENTS.md` / `CLAUDE.md` files — your convention docs are read-only to
  the AI (it proposes changes as separate PRs instead). You can always edit them
  yourself; the guard never touches your own editor or terminal.
- **Your terminal is never guarded.** The push guard only inspects pushes Claude
  Code itself makes, and only in configured repos — your own `git push` in a shell
  is invisible to it.
- **Only humans merge to your default branch.** The engine pushes feature/story
  branches and opens *draft* PRs; branch protection (not trust) enforces the rest.
  Prefer nothing on GitHub at all? Set `review.delivery: local_diff` — local
  branches and diffs only, pushes hard-blocked.
- **No telemetry.** The engine never phones home. Its only network calls are ones
  you configure (your Linear workspace, your Slack webhook) plus one consent-gated
  download: specialist agent personas fetched from a version-pinned public library
  (details in [Agent roster](#agent-roster-agency-agents); `personas.auto_install:
  false` turns it off — everything then runs on Claude Code's built-in agent).
- **Tiny footprint.** In your repo: `.autodev/deployment.json` (commit it — the
  deployment travels with the repo) plus runtime state under `.autodev/`. It never
  writes into `.claude/settings.json` or your git config.
- **QA never touches production.** Every test and live run applies hermetic
  overrides (`qa.hermetic`) pointing external calls at local/sandbox endpoints; the
  preflight fails if production endpoints are in reach.

## How it works

Work flows through a **ticket board** — the pipeline's single source of truth. Every
step is a card moving through a column (New Request → PRD Review (H) → Ready for AI
Dev → AI Development → AI QA → Human Review (H) → Done — "(H)" marks your moments),
so you watch progress like any sprint board. The board is a zero-setup local one by default; flip `tracker.kind: linear`
to use Linear live, including a mode where you drive everything from Linear tickets
and comments with **no terminal at all** (`intake.mode: linear`).

Each ticket is built by a specialist dev agent in its own git worktree, must ship
tests with its change, then gets QA'd by **fresh agents that didn't write the code**
— three angles (does it meet the criteria · can it be broken · did anything else
regress), looping dev ↔ QA until it passes, with a stuck-detector that escalates to
you rather than guessing. After merges, a clean-room verify re-builds from scratch
and auto-reverts on failure. The full rules live in `reference/manual.md` — the
engine's operating manual.

Two commands put that QA machinery directly in your hands:

- **`/autodev:qa <ticket>`** — deep-dive QA on a ready-to-test ticket: posts a test
  plan, spins the app up hermetically, walks every path with screenshots, and writes
  an evidence-backed report that a second, fresh agent audits adversarially and
  countersigns before it reaches you. No browser driver installed? It offers to set
  one up (with your approval) rather than dead-ending.
- **`/autodev:repro`** — turns "X is broken" into a reproduced, buildable ticket: an
  attempt-capped hunt (default 7, then it **stops** and posts what it tried), and on
  success a complete ticket plus a failing repro test, verified by a cold reader
  re-running the steps from the ticket text alone.

Both are command-initiated (nothing runs ambiently) and both **feed** the human
gates, never replace them.

## Setup reference

**Preflight:** `doctor` runs at the end of `/autodev:init` and any time after —
it checks tools, config, board connectivity, and browser-driver availability, and
prints the fix for anything it flags.

**Teammates:** anyone who pulls a configured repo just installs the plugin (step 1) —
the committed `.autodev/deployment.json` does the rest. For build updates on your
phone, run `/remote-control` in Claude Code and pair the Claude mobile app.

**Optional enhancements — each has a built-in fallback:**

- **Linear** (`tracker.kind: linear`) — the board lives in Linear instead of local
  files. Needs a Linear team + API token; `ops/linear-setup.md` is the walkthrough,
  and `/autodev:init` prints exactly what's left to wire. Without it: the local
  board, which needs nothing.
- **BrainGrid** (`braingrid.enabled`, default on) — a spec-authoring tool the engine
  prefers for PRDs. **Not installed? Nothing breaks** — the engine detects that and
  falls back to its own PM personas automatically. Wiring it up is a 5-step CLI
  install (below).
- **Branch protection** on your default branch — enforces "only humans merge"
  mechanically. GitHub settings, two minutes, strongly recommended.

**One default worth knowing:** `backup.enabled` is on — after each ticket merges to
the feature branch, that branch is pushed to `origin` as a work-in-progress backup
(fast-forward only, never your default branch, never a PR). Working somewhere the
robot shouldn't push? Turn it off, or use `local_diff` delivery which disables all
pushing.

## Two ways to ship the same engine

- **Plugin (default, everything above):** versioned updates from the marketplace,
  zero engine files in your repo.
- **Vendored (`./install.sh <repo>`):** the engine *copied into* the repo at
  `.autodev/engine/` — auditable and pinned in your git history, for teams that
  can't run third-party plugins. Vendored commands are `/autodev-init` ·
  `/autodev-new` · `/autodev-loop` (the qa/repro commands are plugin-only today).
  Pick **one mode per repo** — the installer and the plugin each refuse to double
  up, and `/autodev:init` migrates a vendored repo to the plugin automatically.

## Updating

**Plugin installs:** open `/plugin` → Manage plugins → update `autodev` (or turn on
marketplace auto-update). New engine behavior applies to every configured repo on
its next session; your per-repo config is never touched.

**A repo with autoDev history (pre-plugin install, or an old config):** enabling the
plugin is the whole upgrade — the first session detects history, migrates old engine
files (backed up to `.autodev/backup-vendored/`), upgrades the config schema (new
keys get defaults; your values always win), and reports what was in flight. Review +
commit what it changes. Manual equivalents:

```bash
bash "$PLUGIN_ROOT/scripts/migrate-vendored.sh" .   # old engine files → backup
bash "$PLUGIN_ROOT/scripts/upgrade-config.sh" .     # adds new keys; your values win
```

**Vendored installs:** re-run `./install.sh /path/to/repo` from a current checkout —
idempotent, config preserved, version re-stamped so `doctor` can flag staleness.

## The non-negotiables

- **The board is the only state machine** — every transition is a live status move,
  so operators watch real progress; a per-tick reconcile self-heals dropped moves.
- **Two human gates** — plan approval (Gate 1) and result review (Gate 2) — and
  **only humans merge to the default branch** (branch protection, not trust).
- **Autopilot is two touches, not zero:** PRD in → one approval package (≤10-line
  summary + only the gaps that matter) → approve → parallel lanes build with no
  mid-build questions (only genuine blockers interrupt) → you're called back once,
  at acceptance, with the server running + a do-X-expect-Y checklist.
- **Tests ship with every change; QA runs for real** — three fresh-agent angles
  (conformance · adversarial · regression) on an executable environment; the
  live-browser check is advisory, never an auto-block.
- **dev↔QA loops until it passes** — unbounded while making progress; a
  stuck-detector escalates to a human on no-progress ("ask, don't invent").
- **Post-merge clean-room verify** — fresh checkout + clean install + integrated
  suites after every merge, auto-revert on fail, human prod sign-off at the end.
- **Hermetic always** — QA and live runs never touch production services or creds;
  `doctor` fails when prod endpoints are in reach.
- **Bugs get reproduced before they get fixed** — `intake.bugs: triage` (default:
  flagged for a human) or `pipeline` (repro-test-first: failing test committed
  before the fix, QA verifies red → green).
- **Preview at acceptance** — you sign off on a running product (launched
  hermetically, relaunch one-liner posted on the ticket), not just a diff.
- **Backlog drain is opt-in and gated** (`backlog.enabled`) — idle-time work on
  your existing ticket pile, one approved batch at a time, a vetoable context brief
  posted before any code, Gate 2 never waived, your priority order never re-ranked.
- **Your convention docs are read-only to the AI** — `AGENTS.md` / `CLAUDE.md` are
  obeyed, never edited; convention changes arrive as separate PRs with rationale.
- **Glass-box observability** — every action leaves a board trail: status moves,
  per-tick comments, an optional operator digest, per-feature stats
  (`.autodev/metrics.jsonl`). If it's not on the board, it didn't happen.
- **Built to run unattended** (when you opt into the timer) — stateless heartbeat
  passes, rate-limit auto-pause/resume, and a dead-man watchdog with hung-tick
  recovery.

## Toggles (preferred-optional, degrade gracefully)

| Toggle | Options | Default |
|---|---|---|
| `tracker.kind` | `local` (git-native board — zero setup, no tokens, `tracker.mjs board` view) **or** `linear` (the board is Linear, live) | `local` for new setups (init's default) |
| `tracker.mirror.linear` | local mode: also mirror to Linear async (queued, off the critical path) | `false` |
| `braingrid.enabled` | BrainGrid spec authoring **or** agent (PM + PjM) fallback | `true` (auto-falls-back if absent) |
| `session_mode` | `concierge` (Marj greets, plain English drives) · `signal` (one-line pointer, dormant until invoked) · `silent` | `concierge` |
| `intake.mode` | `cli` (in-session) **or** `linear` (tickets + comments, no terminal) | `cli` |
| `intake.bugs` | `triage` (flag for a human) **or** `pipeline` (repro-test-first fixing) | `triage` |
| `preview.enabled` | launch the assembled feature at acceptance + post URL/relaunch cmd | `true` |
| `backlog.enabled` | idle-time backlog drain (entry-gated batches, own PR each) | `false` |
| `tracker.hierarchy` | `issue` (feature as a board issue) **or** `project` (feature as a Linear Project) | `issue` |
| `review.granularity` | `per_story` (review each ticket) **or** `per_feature` (auto-merge to the feature branch; review the whole) | `per_story` |
| `review.delivery` | `draft_pr` (push + GitHub draft PRs) **or** `local_diff` (no GitHub — local branches + diffs, pushes blocked) | `draft_pr` |
| `review.quality_review` | leanness/dedup pass over the assembled feature at close-out | `true` |
| `backup.enabled` | WIP durability — push the feature branch to `backup.remote` after each story merge (never a PR; no-op under `local_diff`) | `true` |
| `personas.auto_install` | download missing specialist personas on demand (pinned ref) **or** run everything as the fallback agent | `true` |
| `execution.logging` | `quiet` (one line per action) · `normal` (checkpoint comments) · `verbose` (+ diffs) | `normal` |
| `execution.incremental_breakdown` | whole feature at Gate 1 **or** per-milestone on demand | `false` |
| `reporting.cadence` | operator digest: `off` · `hourly` · `<N>m` → log / slack / linear | `off` |

## BrainGrid CLI + Claude Code (optional spec tool)

BrainGrid is the **preferred** spec tool (`braingrid.enabled: true`) — it authors the
PRD (`/specify`) and breakdown inside Claude Code. It's **optional**: without it, the
engine falls back to its product-manager + project-manager-senior personas
automatically. To wire it up (needs Node 18+):

```bash
# in your terminal:
npm install -g @braingrid/cli          # 1. install the CLI
braingrid login                        # 2. authenticate (opens a browser)
braingrid setup claude-code            # 3. adds /specify, /breakdown, /build to Claude Code
cd /path/to/target-repo && braingrid init   # 4. create/link a BrainGrid project
braingrid status                       # 5. verify: auth + linked project
```

Then set `braingrid.enabled: true` and `braingrid.project_short_id` in
`.autodev/deployment.json`.

## Agent roster (agency-agents)

The engine routes work to specialist personas from
**[agency-agents](https://github.com/msitarzewski/agency-agents)** by
[@msitarzewski](https://github.com/msitarzewski) (MIT). autoDev doesn't bundle them —
it **installs them on demand**: before a persona is spawned,
`scripts/ensure-personas.sh` resolves the deployment's roster against
`~/.claude/agents/` and downloads **only what's missing, only what this deployment's
config actually routes to**, from a **pinned ref** of the library
(`personas.library.ref` — bump it deliberately). Already have the library, or your
own agents under the same names? Nothing is touched. Air-gapped, or a no-third-party
policy? Set `personas.auto_install: false` — no network, ever; anything unresolved
runs as `personas.fallback` (default `general-purpose`, built into Claude Code), so
**specialists are an upgrade, never a dependency**. `doctor` shows the resolution
state without downloading. Routing lives in `.autodev/deployment.json` (`personas.*`):

| Role | Persona |
|---|---|
| PRD · Breakdown | product-manager · project-manager-senior |
| Dev (routed by files) | backend-architect · frontend-developer · database-optimizer · architect-ux / ui-designer |
| QA — conformance · adversarial · regression/verdict | code-reviewer · test-results-analyzer · evidence-collector · application-security-engineer · api-tester · **reality-checker** |
| QA — visual/UI (conditional, UI-heavy stories) | evidence-collector · **ui-designer** · **architect-ux** (design fidelity · theme adherence · responsive · visual a11y; advisory) |

## Status

**v1 — complete, validated, and hardened by a real run.** Proven end-to-end in a
sandbox (full feature build + dev↔QA loop), then run **20 hours autonomously on a
production codebase** — every gap that surfaced is folded back in
([`BACKLOG.md`](./BACKLOG.md)): hermetic safety, acceptance QA, leanness review,
operator digest, per-feature metrics, hung-tick recovery, and more. Recent additions:
the autoQA commands (`/autodev:qa`, `/autodev:repro`) and on-demand persona install.

## Managed service

autoDev is **free to self-host** under Apache-2.0. If you'd rather not run it
yourself, **managed hosting + onboarding** (we install it into your repo, wire up
Linear + GitHub + CI, and operate the engine for you) is available as a paid
service — reach out to the maintainer.

## Credits

- **[agency-agents](https://github.com/msitarzewski/agency-agents)** by
  [@msitarzewski](https://github.com/msitarzewski) — the specialist persona library
  the engine routes to (**MIT**). Fetched on demand from its own repo at a pinned
  ref; not redistributed here.
- Built to run on **[Claude Code](https://claude.com/claude-code)**, with optional
  **[Linear](https://linear.app)** (board + state) and
  **[BrainGrid](https://braingrid.ai)** (spec authoring).

## License

autoDev is licensed under **[Apache-2.0](./LICENSE)** — free to use, modify, and
self-host. Third-party components keep their own licenses (agency-agents is MIT;
see above).

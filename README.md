# autoDev — describe work in plain English; get QA'd, human-reviewed code

autoDev is a [Claude Code](https://claude.com/claude-code) plugin that runs a
PM → dev team → QA pipeline on your repo. You describe what you want; it writes the
spec, breaks it into tickets on a board you can watch, builds each one, QA's its own
work from three angles, and hands you the result for review. **You stay in charge at
exactly two moments:** you approve the plan before anything is built (Gate 1), and
you approve the result before anything ships (Gate 2). Only humans merge — and
nothing advances until you run the next `/autodev:loop`: you are the engine's clock.

> **Validated end-to-end** in a sandbox (a 15-story landing page built autonomously,
> 144 unit + 24 e2e tests green) **and hardened by a 20-hour autonomous production
> run** — the gaps that surfaced are folded back in (see [`BACKLOG.md`](./BACKLOG.md)).
>
> **Open source (Apache-2.0).** Free to self-host. **Managed hosting + onboarding
> available** — see [Managed service](#managed-service).

## Your first 30 minutes

You need: Claude Code (logged in with a claude.ai subscription), plus `git`, `node`
18+, and `jq` installed — and for the default GitHub delivery, `gh` and a GitHub
remote (no GitHub? choose `review.delivery: local_diff` at setup and skip both).
Don't audit this list by hand: setup ends with a preflight that verifies every tool
and prints the fix for anything missing.

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
Gate 1 — the summary appears **right in the chat**, and nothing gets built until
you've typed **"approved"** in that same chat (or told it what to change; on a
Linear board, moving the card works too). After you approve, keep running
`/autodev:loop` — it breaks the spec into tickets and builds them one by one. A
small three-ticket feature is a handful of calls: one for the spec, one for the
breakdown, then roughly one to three per ticket. Watch the board anytime: ask
"what's the status?", or open `.autodev/board.html` in a browser — it's refreshed
every time the board is viewed or queried, so re-ask to re-render it.

**5 · Review the result (Gate 2).** You never need to read the code. In hands-on
mode each finished ticket arrives as a GitHub *draft* PR with the QA reports and a
**manual test script** attached — follow the script like a user, not a code
reviewer. When the whole feature assembles, it's **launched for you** (preview is on
by default): a URL plus a checklist ("do X → expect Y") — in autopilot, that
running-feature review is the one time you're called back at all. Click through it
like a customer and say "approved" (or what's broken). To ship: on GitHub, mark the
draft PR **"Ready for review"**, then **Merge** (a draft can't be merged until then).

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
- **No telemetry.** The engine never phones home. Its only network calls are for
  tools you configure (GitHub pushes/PRs per your delivery mode, your Linear
  workspace, your Slack webhook, BrainGrid if you install it) plus one
  consent-gated download: specialist agent personas fetched
  from a version-pinned public library (details in
  [Agent roster](#agent-roster-agency-agents); `personas.auto_install: false` turns
  the download off — anything not already installed then runs as the built-in
  fallback agent).
- **Tiny footprint.** In your repo: `.autodev/deployment.json` (commit it — the
  deployment travels with the repo), runtime state under `.autodev/`, and a small
  identity pointer at `.claude/CLAUDE.md` — written only when that slot is empty or
  holds a previous pointer; a team-authored file there is never touched. It never
  writes into `.claude/settings.json` or your git config.
- **QA never touches production.** Every test and live run applies hermetic
  overrides (`qa.hermetic`) pointing external calls at local/sandbox endpoints; the
  preflight fails when production endpoints are present and those overrides are off.

## How it works

Work flows through a **ticket board** — the pipeline's single source of truth. Every
step is a card moving through a column (New Request → PRD Review (H) → Ready for AI
Dev → AI Development → AI QA → Human Review (H) → Done, with Clarifying/Breakdown/
Blocked columns alongside — "(H)" marks your moments),
so you watch progress like any sprint board. The board is a zero-setup local one by default; flip `tracker.kind: linear`
to use Linear live, including a mode where you drive everything from Linear tickets
and comments with **no terminal at all** (`intake.mode: linear`).

Each ticket is built by a specialist dev agent in its own git worktree, must ship
tests with its change, then gets QA'd by **fresh agents that didn't write the code**
— three angles (does it meet the criteria · can it be broken · did anything else
regress), looping dev ↔ QA until it passes. Missing or ambiguous information at
*any* stage means it asks you (or parks the ticket as Blocked with the question) —
it never picks an interpretation and ships it; a stuck-detector escalates
no-progress loops the same way. After merges, a clean-room verify re-builds from scratch
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

**Preflight:** `doctor` runs at the end of `/autodev:init`; re-run it any time by
asking in Claude Code, *"run the autoDev preflight (doctor)"* — it's a script the
assistant runs for you. It checks tools, config, board connectivity, and
browser-driver availability, and prints the fix for anything it flags.

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
  mechanically. Two minutes on GitHub: repo **Settings → Branches → Add branch
  protection rule** on `main`, check *"Require a pull request before merging"*.
  Strongly recommended.

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
  Pick **one mode per repo** — the installer refuses to run where the plugin is
  enabled, and `/autodev:init` migrates a vendored repo to the plugin automatically.

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
bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-vendored.sh" .   # old engine files → backup
bash "${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-config.sh" .     # adds new keys; your values win
```

**Vendored installs:** re-run `./install.sh /path/to/repo` from a current checkout —
idempotent, config preserved, and the engine version is re-stamped into
`deployment.json` so you can see exactly what's deployed.

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
- **Ask, don't invent — at any stage.** Missing, ambiguous, or contradictory info
  → the engine asks (live in-session, or via a Blocked ticket), never guesses.
  dev↔QA loops are unbounded while making progress; a stuck-detector escalates
  no-progress to a human the same way.
- **Post-merge clean-room verify** — fresh checkout + clean install + integrated
  suites after every merge, auto-revert on fail, human prod sign-off at the end.
- **Hermetic always** — QA and live runs never touch production services or creds;
  `doctor` fails when prod endpoints are present and the hermetic overrides are off.
- **Bugs get reproduced before they get fixed** — `intake.bugs: triage` (default:
  flagged for a human) or `pipeline` (repro-test-first: failing test committed
  before the fix, QA verifies red → green).
- **Preview at acceptance** — you sign off on a running product (launched
  hermetically, relaunch one-liner posted on the ticket), not just a diff.
- **Backlog drain is opt-in and gated** (`backlog.enabled`) — idle-time work on
  your existing ticket pile, one approved batch at a time, a vetoable context brief
  posted before any code, Gate 2 never waived, your priority order never re-ranked.
- **Own lane on a shared board** — the engine acts only on tickets it created
  (tagged with its instance label) or that you explicitly hand it; several autoDev
  instances — and your team's own tickets — can share one board untouched.
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
| Dev (routed by files) | backend-architect · frontend-developer · database-optimizer · architect-ux |
| QA — conformance · adversarial · regression/verdict | code-reviewer · test-results-analyzer · evidence-collector · application-security-engineer · api-tester · **reality-checker** |
| QA — visual/UI (conditional, UI-heavy stories) | evidence-collector · **ui-designer** · **architect-ux** (design fidelity · theme adherence · responsive · visual a11y; advisory) |

## Status

**v2 (2.1.0) — validated, and hardened by a real run.** Proven end-to-end in a
sandbox (full feature build + dev↔QA loop), then run **20 hours autonomously on a
production codebase** — every gap that surfaced is folded back in
([`BACKLOG.md`](./BACKLOG.md)): hermetic safety, acceptance QA, leanness review,
operator digest, per-feature metrics, hung-tick recovery, and more. Recent additions:
the autoQA commands (`/autodev:qa`, `/autodev:repro`) and on-demand persona install.

## FAQ

**What does installing this do to my other repos?**
Nothing. In repos without `.autodev/deployment.json`, the hooks exit silently — no
greeting, no files, no behavior change. One deliberate exception, disclosed above:
in any repo, *Claude Code* is blocked from editing `AGENTS.md`/`CLAUDE.md` (your own
editor and terminal never are).

**Does it phone home?**
No telemetry. Network calls happen only for tools you configure (GitHub, Linear,
Slack, BrainGrid) plus the consent-gated persona download from a pinned ref —
`personas.auto_install: false` disables that too.

**Can it merge to `main` or mess up my GitHub?**
No. Only humans merge; the engine pushes feature/story branches and opens *draft*
PRs. With branch protection on, GitHub enforces that mechanically. `local_diff` mode
blocks all pushing.

**Can I undo what it builds?**
Yes. Everything lands on branches behind unmerged PRs — close the PR, delete the
branch, done. After a merge, the clean-room verify auto-reverts anything that breaks
the integrated build.

**What does it cost?**
Your existing Claude subscription — no API key, no separate bill. A feature is many
agent-hours, so expect meaningful quota use; you control the burn by how often you
run `/autodev:loop`, and nothing runs between calls.

**How long does a feature take?**
Each `/autodev:loop` call is one bounded step: a small three-ticket feature is
roughly one call for the spec, one for the breakdown, one to three per ticket, and
a close-out — call it a dozen for a small feature, spread however you like.

**Is anything running when I'm not looking?**
No — no daemon, no background work between calls, unless you deliberately wire the
optional 24/7 timer (`ops/launchd-timer.md`).

**Do I need to be able to read code?**
No. Every ticket arrives with QA reports and a manual test script, and the
assembled feature is launched for you at acceptance — a URL plus a do-X-expect-Y
checklist. Judge it like a customer.

**Does my project need to be on GitHub?**
Only for the default draft-PR delivery. `review.delivery: local_diff` keeps
everything local — branches and diffs, no pushes, no `gh` needed.

**What if I don't know git?**
The engine drives git. Your verbs are "approved", "what's the status?", and
GitHub's Merge button.

**How do I re-run the health check?**
In Claude Code, ask: *"run the autoDev preflight (doctor)"*. It checks tools,
config, board connectivity, and the browser driver, and prints the fix for
anything it flags.

**What happens if I run `/autodev:loop` in a repo I never set up?**
It notices there's no config and walks you through setup first (the same questions
as `/autodev:init`), then continues with your work.

**How is this different from just asking Claude Code to build the feature?**
Structure and audit: a board as the single source of truth, two human gates, QA by
fresh agents that didn't write the code, tests required with every change, and a
comment trail for every action — instead of one long chat you have to babysit.

**Can my team use it — or several instances on one board?**
Yes. Teammates just install the plugin; the committed `.autodev/deployment.json`
does the rest. Each instance only touches tickets tagged with its own label, so
several autoDevs — and your team's own tickets — coexist on one board safely.

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

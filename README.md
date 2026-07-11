# autoDev — an autonomous development engine, as a Claude Code plugin

autoDev turns an idea into **QA'd, human-reviewable, shipped code** through a
ticketing board (Linear or a git-native local board), driven by Claude Code —
mimicking a PM → dev team, made operable by non-technical people. It ships **two
ways from the same engine** (pick ONE per repo):

- **Plugin (default):** enable it, run `/autodev:init`, done — versioned updates from
  the marketplace, hooks active on install, zero engine files in your repo.
- **Vendored (`./install.sh <repo>`):** the same engine copied into the repo at
  `.autodev/engine/` — auditable and pinned in *your* git history, for teams that
  can't or won't run a third-party plugin. Commands become `/autodev-init` ·
  `/autodev-new` · `/autodev-loop`; switching to the plugin later is automatic
  (`/autodev:init` migrates vendored installs).

> **Validated end-to-end** in a sandbox (a 15-story landing page built autonomously,
> 144 unit + 24 e2e green) **and hardened by a 20-hour autonomous production run** —
> the gaps that surfaced are folded back in (see [`BACKLOG.md`](./BACKLOG.md)).
>
> **Open source (Apache-2.0).** Free to self-host. **Managed hosting + onboarding
> available** — see [Managed service](#managed-service).

## What you get

autoDev ships as a **Claude Code plugin** — nothing is copied into your repo.
Enabling it adds five commands and a couple of guardrail hooks; everything else
(the engine manual, the per-stage playbooks, the scripts) lives inside the plugin
package and is read at runtime via `${CLAUDE_PLUGIN_ROOT}`.

```
autodev/                              (the plugin package)
├── .claude-plugin/plugin.json        # plugin manifest
├── commands/
│   ├── init.md                       # /autodev:init  — guided one-time setup, writes .autodev/deployment.json
│   ├── new.md                        # /autodev:new   — the only way work enters the engine
│   ├── loop.md                       # /autodev:loop  — advance one bounded step (PRD → breakdown → dev/QA → merge-verify)
│   ├── qa.md                         # /autodev:qa    — deep-dive exploratory QA on one ready-to-test ticket
│   └── repro.md                      # /autodev:repro — reproduce a bug into a verified, buildable ticket
├── reference/                        # playbooks — read explicitly by the commands above; never auto-triggered
│   ├── manual.md                     # engine manual: concierge routing, non-negotiables, toggles
│   ├── intake.md · prd.md · breakdown.md · devloop.md · deep-qa.md · repro.md · merge-verify.md · story-template.md
│   └── deployment.example.json       # the full config schema, used by /autodev:init
├── scripts/                          # tracker.mjs · linear.mjs · report.mjs · doctor.sh · detect-conventions.sh ·
│                                      # check-docs.sh · devloop-tick.sh · watchdog.sh · notify.sh ·
│                                      # write-identity-pointer.sh
├── hooks/hooks.json                  # a one-line SessionStart signal + two PreToolUse guardrails (push, docs) — no settings.json write, ever
├── ops/{linear-setup.md, launchd-timer.md, launchd.plist.template}
├── BACKLOG.md
└── docs/
```

In a client repo, the **entire footprint** is `.autodev/deployment.json` plus
runtime state created lazily on first use (`.autodev/board/`, `conventions.md`,
`metrics.jsonl`, `logs/`). Nothing under `.claude/` is ever written.

### autoQA — deep QA and bug reproduction, on demand

Two of those commands put the engine's QA machinery in your hands directly.
**`/autodev:qa <ticket>`** takes a ready-to-test ticket and goes deep: posts a test
plan, spins the app up hermetically, walks every path with screenshots, and writes an
evidence-backed report — which a second, fresh agent audits adversarially
(claim-to-evidence, coverage vs the plan, spot re-runs) and countersigns before it
reaches you. **`/autodev:repro`** turns "X is broken" into a reproduced, buildable
ticket: an attempt-capped hunt (default 7, then it **stops** and posts its attempted
matrix), and on success a complete ticket plus a failing repro test — verified by a
cold reader re-running the steps from the ticket text alone — queued for the dev
pipeline. Both are command-initiated (nothing runs ambiently), and both **feed** the
human gates, never replace them. Depth: `reference/deep-qa.md` ·
`reference/repro.md` · the design brief (`docs/briefs/2026-07-10-autoqa-autopr.md`).

## Onboarding

**Prerequisites:** Claude Code with a claude.ai subscription login, plus `git`, `node`
(18+), and `jq` on PATH (the tracker/doctor scripts use them).

**1 · Enable the plugin — once per machine:**

```
/plugin marketplace add eschnei/autodev
/plugin install autodev@autodev-marketplace
```

Installing is the consent step — the plugin's hooks (session identity, push/docs
guards) are active immediately, in every repo, with no per-workspace trust dance.

**2 · Set up a repo:**

```
/autodev:init      # guided: detects branch/commands from the repo, asks ~5 questions
                   # (incl. hands-on vs autopilot, concierge vs quiet sessions),
                   # defaults to the zero-setup LOCAL board, writes .autodev/deployment.json
/autodev:new       # capture the first piece of work
/autodev:loop      # advance it — re-run any time; nothing runs between calls unless you
                   # wire the 24/7 timer (ops/launchd-timer.md)
/autodev:qa AD-12  # deep-dive QA a ticket that's ready to test — plan, evidence,
                   # independently verified report posted for your review
/autodev:repro     # turn "X is broken" into a reproduced, buildable ticket
                   # (or a documented can't-reproduce) before a dev cycle is spent
```

With the default `session_mode: concierge`, your next session simply opens with the
assistant (Marj) greeting you with a status snapshot — from there it's plain English:
"here's the PRD", "what's the status?", "grab AD-12", "QA AD-12 deeply", "can you
reproduce this bug?". The commands are shortcuts, not
requirements. `.autodev/deployment.json` is the entire per-repo footprint — commit it
so the deployment travels with the repo. BrainGrid, Linear, and branch-protection
wiring remain manual, auth-bound steps — `/autodev:init` prints exactly what's left.

**Teammates:** anyone who pulls a configured repo just enables the plugin the same way
(step 1) — the repo's `.autodev/deployment.json` does the rest. To get build updates on
your phone, run `/remote-control` and pair the Claude mobile app (enable push in `/config`).

**No-plugin alternative (vendored):** `./install.sh /path/to/repo` copies this same
engine into the repo at `.autodev/engine/` — auditable and version-pinned in *your*
git history; commands become `/autodev-init` · `/autodev-new` · `/autodev-loop`.
Pick **one mode per repo** (the installer and the plugin each refuse to double up).

## Updating

**Plugin installs:** updates come from the marketplace — open `/plugin` → Manage
plugins → update `autodev` (or turn on auto-update for the marketplace). New engine
behavior applies to every configured repo on its next session; per-repo config is
never touched by a plugin update.

**A repo with autoDev history (pre-plugin install, or an old config):** enabling the
plugin is the whole upgrade. The first session **detects the history** and updates
in place — migrates old committed engine files (backed up to
`.autodev/backup-vendored/`, team files restored), **upgrades the config schema**
(new keys get defaults; every value you set is preserved), then reports what was
already in flight (feature branches, board stories) — history continues, it doesn't
restart. Review + commit the changes it makes. Manual equivalents:

```bash
bash "$PLUGIN_ROOT/scripts/migrate-vendored.sh" .   # old engine files → backup, team files restored
bash "$PLUGIN_ROOT/scripts/upgrade-config.sh" .     # adds new config keys; your values win; prints what it added
```

**Vendored installs:** re-run `./install.sh /path/to/repo` from a current engine
checkout — it upgrades `.autodev/engine/` in place (idempotent; your settings-file
entries and config are preserved) and re-stamps the version so `doctor` can flag
staleness. Switching a vendored repo to the plugin later: enable the plugin and let
the first session migrate it, exactly as above.

## The non-negotiables

- **How much autoDev greets you is a toggle (`session_mode`) — and it stays in its own
  files.** In a configured repo, **`concierge` (default)** gives you the full assistant:
  it greets by name (Marj, unless renamed) with a status snapshot, routes plain English —
  *you never need to remember a command* — and narrates builds ambiently. **`signal`**
  keeps the engine dormant behind a one-line pointer until an `/autodev:*`
  command (right for dual-use repos); **`silent`** says nothing. Unconfigured
  repos always get nothing. Either way the engine manual lives in the plugin's
  **`reference/manual.md`** (never your `CLAUDE.md`), and **your `AGENTS.md` /
  `CLAUDE.md` stay the authority on coding conventions** — autoDev reads and obeys them,
  and a `PreToolUse` hook denies any Edit/Write to them; a convention change comes as a
  separate PR with rationale, never a silent in-place edit.
- **The board is the only state machine** — every transition is a live status move
  (`tracker.mjs move …`); cards flow through every column so non-technical operators
  watch work progress in real time. A per-tick reconcile self-heals dropped moves.
  **Where the board lives is a toggle** (`tracker.kind`): a **git-native local board**
  (zero setup, no tokens, no rate limits, optional async Linear mirror) or Linear live.
- **Two human gates** — PRD approval (Gate 1), story/feature review (Gate 2) — and
  **only humans merge to the default branch** (branch protection, not trust).
- **Autopilot mode (the PM handoff):** hand over a PRD → get ONE approval package
  (≤10-line summary + only the gaps that matter) → approve → tickets build themselves
  and **parallel lanes execute with no mid-build questions** (only genuine Blocks
  interrupt) → you're called back once, at acceptance, with the **server already
  running + a to-the-point test checklist** (do X → at URL → expect Y). Set
  `review.granularity: per_feature` + `auto_merge_to_feature_branch: true`, or pick
  "autopilot" in `/autodev:init`. Progress updates stay ambient — and to get
  them **on your phone**, run `/remote-control` in Claude Code and pair the Claude
  mobile app (enable push in `/config` to get pinged when the build lands or needs you).
- **Tests ship with every change; QA runs for real** — three angles (conformance ·
  adversarial · regression), hidden adversarial tests, on an executable env. The
  **live-browser check is advisory**, never an auto-block.
- **dev↔QA loops until it passes** — QA fail → back to dev → retry, *unbounded while
  making progress*; a **stuck-detector** escalates to a human only on no-progress
  (= "ask, don't invent").
- **Post-merge clean-room verify + whole-feature acceptance** — fresh checkout +
  clean install + integrated suites + live smoke after every merge (auto-revert on
  fail) → acceptance report → **human prod sign-off**. Kills "worked on my local."
- **Hermetic always (safety)** — every test/build/app/live run applies
  `qa.hermetic` overrides; the engine **never** drives QA or the live app against
  production services/creds, and `doctor` fails on prod endpoints in `.env`.
- **Feature-vs-bug gate** at intake — `intake.bugs`: `triage` (default — flagged for a
  human, not built) or `pipeline` (**repro-test-first**: intake demands a reproduction,
  the dev agent commits a failing repro test before fixing, QA verifies red → green).
- **Preview at acceptance** (`preview.enabled`) — the human signs off on a **running
  product** (assembled feature branch launched hermetically + relaunch one-liner posted
  on the ticket), not just a diff and a report.
- **Backlog drain (`backlog.enabled`, opt-in)** — when nothing else is in flight, the
  engine can chew through the team's existing backlog/bug pile: you approve a **batch**
  at an entry gate, then each ticket gets explore-the-code → a **context brief with
  derived, testable criteria posted on the ticket** (the PRD substitute — vetoable
  before a line is written) → build (bugs repro-test-first) → full QA → **its own PR**
  for human review. Unfit tickets are commented + skipped, never guessed at; real
  feature work always preempts; the team's priority order is never re-ranked.
- **Glass-box observability** — status moves + per-tick comment logging + an
  operator digest + a per-feature stats record (`.autodev/metrics.jsonl`).
- **Stateless heartbeat** passes · rate-limit auto-pause/resume · dead-man watchdog
  (with hung-tick recovery).

## Toggles (preferred-optional, degrade gracefully)

| Toggle | Options | Default |
|---|---|---|
| `tracker.kind` | `local` (git-native board — zero setup, no tokens/rate limits, `tracker.mjs board` view) **or** `linear` (the board is Linear, live) | `linear` (existing) · `local` recommended for new |
| `tracker.mirror.linear` | local mode: also mirror to Linear async (queued + coalesced, off the critical path) | `false` |
| `braingrid.enabled` | BrainGrid spec authoring **or** agent (PM + PjM) fallback | `true` |
| `session_mode` | `concierge` (full Marj at session start — plain English, no commands) · `signal` (one-line pointer, dormant until invoked) · `silent` | `concierge` |
| `intake.mode` | `cli` (in-session) **or** `linear` (ticket + comments, no terminal) | `cli` |
| `intake.bugs` | `triage` (flag for a human) **or** `pipeline` (repro-test-first bug fixing) | `triage` |
| `preview.enabled` | launch the assembled feature at the acceptance gate + post URL/relaunch cmd | `true` |
| `backlog.enabled` | **backlog drain**: work the team's existing ticket pile during idle time — entry-gate approval per batch (`backlog.batch`), context-brief-instead-of-PRD per ticket, own PR each, Gate 2 never waived | `false` |
| `tracker.hierarchy` | `issue` (feature on the board) **or** `project` (feature-as-Project, org-wide statuses) | `issue` |
| `review.granularity` | `per_story` (review each) **or** `per_feature` (auto-merge to branch; review the whole) | `per_story` |
| `review.delivery` | `draft_pr` (push + GitHub PRs) **or** `local_diff` (no GitHub — local branches + diffs only) | `draft_pr` |
| `review.quality_review` | leanness/dedup pass over the assembled feature diff at close-out | `true` |
| `backup.enabled` | WIP durability — push the feature branch to `backup.remote` on creation + after every story merge (not a PR; `draft_pr` only, no-op under `local_diff`) | `true` |
| `execution.logging` | `quiet` (status only) · `normal` (checkpoint comments) · `verbose` (+ diffs) | `normal` |
| `execution.incremental_breakdown` | break down the whole feature at Gate 1 **or** per-milestone on demand | `false` |
| `reporting.cadence` | operator digest: `off` · `hourly` · `<N>m` → log / slack / linear | `off` |

## BrainGrid CLI + Claude Code (optional spec tool)

BrainGrid is the **preferred** spec tool (`braingrid.enabled: true`) — it authors the
PRD (`/specify`) and breakdown directly inside Claude Code. It's **optional**: with
no BrainGrid, the engine falls back to the product-manager + project-manager-senior
personas. To wire it up (needs Node 18+):

```bash
# 1. Install the CLI
npm install -g @braingrid/cli

# 2. Authenticate (opens a browser)
braingrid login

# 3. Install the Claude Code integration — adds the /specify, /breakdown, /build
#    slash commands to Claude Code (run --force to overwrite existing files)
braingrid setup claude-code

# 4. In the TARGET repo: create/link a BrainGrid project
cd /path/to/target-repo && braingrid init
#    (non-interactive: braingrid project create --name "<Name>" --repository owner/repo,
#     then braingrid init --project <id>)

# 5. Verify
braingrid status        # shows auth + the linked project
```

Then set `braingrid.enabled: true` and `braingrid.project_short_id` in the deployment
config. (`braingrid setup cursor` / `openclaw` exist too, but autoDev uses Claude Code.)

## Agent roster (agency-agents)

The engine routes work to specialist personas from **[agency-agents](https://github.com/msitarzewski/agency-agents)**
by [@msitarzewski](https://github.com/msitarzewski) (MIT). autoDev doesn't bundle
them — it **installs them on demand**: before a persona is spawned,
`scripts/ensure-personas.sh` resolves the deployment's roster against
`~/.claude/agents/` and downloads **only what's missing, only what this
deployment's config actually routes to**, from a **pinned ref** of the library
(`personas.library.ref` — bump it deliberately). Already have the library, or your
own agents under the same names? Nothing is touched. Air-gapped, or a no-third-party
policy? Set `personas.auto_install: false` — no network, ever; anything unresolved
simply runs as `personas.fallback` (default `general-purpose`, built into Claude
Code), so **specialists are an upgrade, never a dependency**. `doctor.sh` shows the
resolution state without downloading. Routing lives in
`.autodev/deployment.json` (`personas.*`):

| Role | Persona |
|---|---|
| PRD · Breakdown | product-manager · project-manager-senior |
| Dev (routed by files) | backend-architect · frontend-developer · database-optimizer · architect-ux / ui-designer |
| QA — conformance · adversarial · regression/verdict | code-reviewer · test-results-analyzer · evidence-collector · application-security-engineer · api-tester · **reality-checker** |
| QA — visual/UI (conditional, UI-heavy stories) | evidence-collector · **ui-designer** · **architect-ux** (design fidelity · theme adherence · responsive · visual a11y; advisory) |

## Status

**v1 — complete, validated, and hardened by a real run.** Proven end-to-end in a
sandbox (full feature build + dev↔QA loop), then run **20 hours autonomously on a
production codebase** — every gap that surfaced is folded back in ([`BACKLOG.md`](./BACKLOG.md)):
hermetic safety, acceptance QA, leanness review, operator digest, per-feature metrics,
hung-tick recovery, a self-sufficient Linear helper, and more. Next: deploy onto a
dedicated always-on machine and enable the 24/7 timer.

## Managed service

autoDev is **free to self-host** under Apache-2.0. If you'd rather not run it
yourself, **managed hosting + onboarding** (we install it into your repo, wire up
Linear + GitHub + CI, and operate the engine for you) is available as a paid
service — reach out to the maintainer.

## Credits

- **[agency-agents](https://github.com/msitarzewski/agency-agents)** by
  [@msitarzewski](https://github.com/msitarzewski) — the specialist persona library
  the engine routes to (**MIT**). Installed by the operator; not redistributed here.
- Built to run on **[Linear](https://linear.app)** (board + state),
  **[BrainGrid](https://braingrid.ai)** (spec authoring, optional), and
  **[Claude Code](https://claude.com/claude-code)**.

## License

autoDev is licensed under **[Apache-2.0](./LICENSE)** — free to use, modify, and
self-host. Third-party components keep their own licenses (agency-agents is MIT;
see above).

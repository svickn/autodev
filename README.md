# autoDev — an autonomous development engine, as a Claude Code plugin

autoDev turns an idea into **QA'd, human-reviewable, shipped code** through a
ticketing board (Linear), driven by Claude Code — mimicking a PM → dev team, made
operable by non-technical people. It ships as a **Claude Code plugin**: enable it
in any repo, run `/autodev:init`, and it drives — no install script, no config
file to copy.

> **Validated end-to-end** in a sandbox (a 15-story landing page built autonomously,
> 144 unit + 24 e2e green) **and hardened by a 20-hour autonomous production run** —
> the gaps that surfaced are folded back in (see [`BACKLOG.md`](./BACKLOG.md)).
>
> **Open source (Apache-2.0).** Free to self-host. **Managed hosting + onboarding
> available** — see [Managed service](#managed-service).

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

## The non-negotiables

- **autoDev only drives when you tell it to — and stays in its own files.** Nothing runs
  from plain conversation; only **`/autodev:init`**, **`/autodev:new`**, and
  **`/autodev:loop`** do anything. The engine manual lives in the plugin's
  **`reference/manual.md`** (never your `CLAUDE.md`) and is read explicitly by those
  three commands — a one-line `SessionStart` hook is the only ambient behavior, and it
  just tells you the commands exist. **Your `AGENTS.md` / `CLAUDE.md` stay the authority
  on coding conventions** — autoDev reads and obeys them, and a `PreToolUse` hook denies
  any Edit/Write to them; a convention change comes as a separate PR with rationale,
  never a silent in-place edit.
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
| `intake.mode` | `cli` (in-session) **or** `linear` (ticket + comments, no terminal) | `cli` |
| `intake.bugs` | `triage` (flag for a human) **or** `pipeline` (repro-test-first bug fixing) | `triage` |
| `preview.enabled` | launch the assembled feature at the acceptance gate + post URL/relaunch cmd | `true` |
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
by [@msitarzewski](https://github.com/msitarzewski) (MIT). autoDev does **not** bundle
them — install them into `~/.claude/agents/` from that repo; routing lives in
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

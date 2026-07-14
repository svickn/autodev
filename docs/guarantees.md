# autoDev guarantees & configuration

The engine's rules of engagement, every toggle, and the agent roster. The full
operating manual the engine itself follows is `reference/manual.md`.

## The board

Work flows through a **ticket board** — the pipeline's single source of truth. Every
step is a card moving through a column (New Request → PRD Review (H) → Ready for AI
Dev → AI Development → AI QA → Human Review (H) → Done, with Clarifying/Breakdown/
Blocked columns alongside — "(H)" marks your moments), so you watch progress like
any sprint board. The board is a zero-setup local one by default; flip
`tracker.kind: linear` to use Linear live — including a mode where you drive
everything from Linear tickets and comments with **no terminal at all**
(`intake.mode: linear`) — or `tracker.kind: shortcut` to use Shortcut live
(in-session intake; see `ops/shortcut-setup.md`).

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
| `tracker.kind` | `local` (git-native board — zero setup, no tokens, `tracker.mjs board` view) · `linear` (the board is Linear, live) · `shortcut` (the board is Shortcut, live; cli intake) | `local` for new setups (init's default) |
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

# deep-qa — one ticket, unbounded exploratory QA, evidence or it didn't happen

> Read by `/autodev:qa` — human-invoked, on ONE ticket the operator names (their
> invocation IS the principle-10 authorization to work it). This is the unbounded
> exploration the heartbeat's per-story QA (`reference/devloop.md` §6) can't afford:
> the loop gets a bounded pass, deep-qa gets as long as the paths take. **The report
> FEEDS Gate 2, it never passes one** — this playbook renders no merge/approve
> authority and never moves a ticket across a human gate. Every action leaves a
> board trail (principle 9): the plan, the report, the countersign, every flag —
> all comments via `node "${CLAUDE_PLUGIN_ROOT}/scripts/tracker.mjs" …`.

Read `.autodev/deployment.json` for `qa.*` (hermetic, docker_up, seed_test,
live_browser_driver, `qa.deep_dive.final_review`), `commands.*` (app_run, app_url),
`personas.qa_angles.verdict`, and `execution.max_dev_qa_loops` (the bounce budget).

## 1 · Plan first — posted before anything runs

From the ticket + PRD acceptance criteria + wireframes/attachments, derive an
explicit **test plan**: the ideal paths (each criterion's happy path), the edge
paths (empty/error/boundary states, permission variants), and the matrix
(breakpoints/browsers where UI, data variants where not). Post it:
`comment <issue> "🧭 deep-QA plan — <paths + matrix>"`. **The posted plan is the
contract** — the final review audits coverage against it, so a path silently
dropped mid-session is caught, not forgotten. Criteria too vague to plan against →
stop and ask the operator before executing (ask, don't invent); note the gap on
the ticket.

## 2 · Hermetic env, then app up (SAFETY — non-negotiable 8)

Export `qa.hermetic.env` before ANY run so external calls hit local/sandbox or are
blanked — **never production**. If prod-looking endpoints are present and
`qa.hermetic.enabled` is false, **stop**: `comment <issue> "🛑 deep-QA refused —
prod endpoints present and hermetic off"` and tell the operator. Then
`qa.docker_up` (data services only) · seed per `qa.seed_test` if the marker
`.autodev/.test_db_seeded` is absent · start the app (`commands.app_run` →
`commands.app_url`). 🗒️ `▶️ deep-QA started · <n> planned paths`.

## 3 · Walk every path — capture as you go

Drive each planned path with `qa.live_browser_driver` (Playwright + Chromium for
UI; live API/runtime checks for non-UI tickets):

- **Screenshot every step**, not just endpoints — save under
  `.autodev/qa/<issue>/` and reference the paths in the report; attach the key
  ones (`tracker.mjs attach`).
- **Capture alongside**: console errors/warnings, failed/hanging network calls,
  and an a11y snapshot (landmarks, focus order, contrast) on each distinct screen.
- Compare rendered screens against attached wireframes where they exist (advisory,
  as in devloop §6).
- **Off-script exploration is in scope** — after the planned paths, poke at what
  looked fragile (double-submits, back-button, stale state, odd viewport). This
  tail is the whole reason deep-qa exists; give it real time.
- App won't start / a path can't be exercised → that's a finding, not a blocker to
  route around silently: record it with evidence and keep walking what's walkable.

Kill anything the session leaked (servers, browsers) when done — 🗒️ `🧹 reaped
<n>` if n>0.

## 4 · The report — every verdict traceable to an artifact

Post one structured report comment on the ticket:

1. **Verdict per planned path** — `✓ / ⚠ / ✗`, one line each: what was done →
   what was expected → what happened, **each citing its evidence**
   (screenshot path / console excerpt / request log). A verdict with no artifact
   doesn't go in the report.
2. **Deviations from criteria** — the specific criterion, the observed gap, the
   evidence.
3. **🔍 Off-script findings** — anything noticed outside the plan (fragility,
   dead ends, visual breakage, console noise), each with evidence and a severity
   guess. Flag, don't judge — these weren't in the contract.
4. **Coverage** — planned vs executed (and why, for anything skipped).

## 5 · Final review — a fresh agent tries to refute the report

When `qa.deep_dive.final_review` (default **true**): spawn the
`personas.qa_angles.verdict` persona **fresh — never the agent that ran the
session** (builder ≠ reviewer, principle 7; the session agent *remembers* things
going well, the reviewer only believes what was captured). It audits:

- **Claim-to-evidence** — every verdict traces to a real artifact; unsupported
  claims are struck or bounced.
- **Coverage vs the posted plan** (§1) — silently dropped paths bounce.
- **Verdict soundness** — findings must support the conclusions (three ⚠s
  summarized as "all good" bounces; a ✓ contradicted by its own screenshot too).
- **Spot re-execution** — re-drive the 1–2 highest-risk claims and compare. This
  is what makes the review verification, not one model agreeing with another.

Outcome: **countersign** — report posts with both signatures, `comment <issue>
"✅ deep-QA report verified — QA by <session persona>, verified by <verdict
persona>"` — or **bounce with specifics** ("path 4 has no evidence; path 7's
screenshot contradicts its ✓"); the session agent patches exactly the named gaps
and resubmits. **Bounces are budgeted by `execution.max_dev_qa_loops`** — still
disagreeing at the cap → post both versions and flag the dispute for the human;
never loop politely forever.

## 6 · Hand-off — feed the gate, don't pass it

- The countersigned report + evidence is the deliverable; it exists to make the
  human's Gate 2 review take minutes.
- **Never** move the ticket across a human gate, merge, or approve on the
  report's strength — that decision is the human's (non-negotiables 2–3).
- Gating-level defects on an engine-owned story MAY route it back to work, same
  as devloop §6's outcome: `move <issue> ai_development --note "❌ deep-QA —
  <the specific defects>"`. Anything else (advisory flags, tickets not owned by
  this instance): comment only, status untouched.
- 🗒️ `🏁 deep-QA done · <n>/<n> paths · <verdict counts> · report + countersign on
  the ticket`.

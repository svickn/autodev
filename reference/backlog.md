# backlog drain — work the existing pile when nothing else is going on

Most teams have a backlog they will never get to (real example: 666 tickets + 287
bugs). This mode lets the engine chew through it **during idle time only** — real
feature work always preempts. It is OFF by default (`backlog.enabled`), and even
when enabled it never starts without an **operator approval at the entry gate**.
These tickets have no PRD, so each one gets a **context-first mini-pipeline**
instead of Gate 1: explore the codebase, derive testable criteria, build, full QA,
PR. Gate 2 (a human reviews + merges every PR) is unchanged.

## 1 · Entry gate — approval to ENTER the mode, not per ticket

Never start draining silently. Ask at exactly these moments (`backlog.ask_when`):
- **`feature_complete`** — a feature just shipped and released the one-feature lock,
  and the queue is empty.
- **`idle`** — `backlog.idle_ticks` consecutive heartbeat passes did nothing.

The ask (concierge session: ask in conversation; headless: create a board issue
`Backlog drain — approve to start (batch of <N>)` in the gate column and wait):
*"Nothing is in flight. Want me to work the backlog? I'll take the top <N>
(`backlog.batch`) by priority, one at a time — each gets a context brief, full QA,
and its own PR for your review. Reply approve / pick different tickets / not now."*

An `approve` **authorizes one batch** (`backlog.batch`, default 3) — this is the
principle-10 operator hand-over, granted once for the batch instead of per ticket.
Record it: 🗒️ audit comment + `touch .autodev/.backlog_authorized` (delete when the
batch completes or authorization is revoked). After each batch: report what shipped,
ask again. "Not now" → don't re-ask until the next `ask_when` trigger fires.

## 2 · Selection — top of the pile, but honest about fitness

Pull from `backlog.source` (tracker-agnostic via `tracker.mjs`; for `kind: linear`
this is a status/label query, e.g. status `Backlog`; `backlog.source.type` filters
`any | bug | feature`). Take the **highest-priority** ticket (tracker priority
field, then list order — assume the team ordered it; don't re-rank on your own).

**Fitness check before adopting** (a bad ticket must not stall the drain):
- Too vague to derive testable criteria even after exploring the code → comment
  `⏭️ needs detail to be workable: <the specific questions>`, label
  `autodev:needs-detail`, **skip to the next ticket** (never Block the whole mode
  on one ticket; the comment IS the ask-don't-invent escalation).
- Clearly stale/already-fixed (the code shows it) → comment the evidence, label
  `autodev:maybe-obsolete`, skip. Never close a ticket — that's the team's call.
- Bigger than one PR-sized change (needs design decisions, touches everything) →
  comment `⏭️ too large for backlog mode — route through /autodev:new for a real
  PRD`, label `autodev:needs-prd`, skip.
On adoption: apply `tracker.instance_label` + `ai-eligible`, move it into the
pipeline columns. 🗒️ `📥 adopted from backlog (batch <i>/<N>) · priority <p>`.

## 3 · Context-first mini-pipeline (replaces Gate 1 for unscoped tickets)

1. **Explore.** Read the ticket fully (description, comments, links). Then build
   real context from the CODE: locate the feature area (grep/read), its tests, its
   conventions (`.autodev/conventions.md` + the team's AGENTS.md/CLAUDE.md), recent
   git history of those files (someone may have half-fixed it).
2. **Context brief — post it on the ticket** (this is the transparency substitute
   for a PRD; a human can veto before a line is written):
   `🧭 context brief:` what the ticket means in THIS codebase · files involved ·
   root cause (bugs) or insertion points (features) · **derived acceptance
   criteria** (testable, from ticket + code reality) · planned approach in ≤5
   lines · risk class. Derived criteria must be checkable — if you can't write
   them, this ticket fails the fitness check (§2), skip.
3. **Build** on its own branch `{story_prefix}/backlog-<id>/<slug>` cut from the
   default branch (backlog tickets are standalone — no feature branch). **Bugs are
   repro-test-first** regardless of `intake.bugs`: failing test committed red →
   fix → green. Features: tests ship with the change, per the standard contract.
   All coding standards apply (conventions survey, comment density, generated
   types, theme tokens).
4. **Full QA** — the standard three angles + conditional visual (devloop §6),
   hermetic, dev↔QA loop with the stuck-detector. A stuck backlog ticket doesn't
   Block and wait — comment the specifics, label `autodev:stuck`, return it to the
   backlog column, **move on to the next ticket** (idle time is for throughput;
   humans triage the stuck pile on their schedule).
5. **Deliver per `review.delivery`** — `draft_pr`: push the branch, open a PR **to
   the default branch** titled from the ticket, body = the context brief + QA
   evidence + test checklist; attach the PR URL to the ticket; move it to the
   review gate column. `local_diff`: present the local diff on the ticket. **A
   human reviews and merges every backlog PR — Gate 2 is never waived.**
6. 🗒️ Log throughout (principle 9) and count each ticket against the batch.

## 4 · Preemption + caps

- **Real work always wins.** A new feature entering intake/breakdown, or any story
  becoming eligible, pauses the drain: finish the in-flight backlog ticket, start
  no new ones, resume only when idle again (no re-approval needed within the batch).
- **One backlog ticket at a time** (no parallel lanes — unscoped work is riskier;
  keep the blast radius one PR).
- The batch cap re-gates the mode; `.backlog_authorized` deleted on completion,
  revocation ("stop the backlog work"), or any `backlog.enabled: false` flip.

## Config (`backlog.*` in .autodev/deployment.json)

`enabled` (false) · `ask_when` (["feature_complete","idle"]) · `idle_ticks` (4) ·
`batch` (3) · `source.status` ("Backlog") · `source.labels` ([]) · `source.type`
("any") — see `reference/deployment.example.json` for the annotated block.

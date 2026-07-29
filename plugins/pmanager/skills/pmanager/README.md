# pmanager — usage guide

Agentic technical project/product manager. You bring a raw problem or idea;
it researches the evidence, frames an epic behind an approval gate, and
decomposes it into a plan and executable tasks under `docs/pm/` — then
tracks that work across sessions.

This file is the all-in-one guide: how to use the skill, what it produces,
and a full worked example. The skill's own behavior is defined in
[SKILL.md](SKILL.md); the templates and playbooks live in
[references/](references/).

## Install

| Target | Command |
| :--- | :--- |
| Claude Code | `/plugin marketplace add glapsfun/cnative-skills` once, then `/plugin install pmanager@cnative-skills` (also registers `/pmanager`) |
| Codex | `npx skills add glapsfun/cnative-skills --skill pmanager --agent codex --global -y` |
| Gemini CLI | `npx skills add glapsfun/cnative-skills --skill pmanager --agent gemini-cli --global -y` |
| Copilot CLI | `npx skills add glapsfun/cnative-skills --skill pmanager --agent copilot --global -y` |

## How to use it

Invoke it explicitly with `/pmanager <request>`, or just describe the work —
the skill triggers on planning/scoping language. Three kinds of request:

**1. New work — a problem or idea:**

```text
/pmanager we have a performance problem in the app — the orders page got slow in July
/pmanager product wants CSV export for the orders reports, break it down for next sprint
/pmanager plan out multi-tenant support as an epic
```

The agent researches your repo first (code, git history, docs, prior
incidents), asks you **only** what research couldn't answer, then shows you
the epic framing — problem, hypothesis, success metric, scope, non-goals —
and **stops for your approval** before writing any plan or tasks.

**2. Updates on tracked work:**

```text
/pmanager T01 of app-performance is done, T02 is blocked on the DBA review
/pmanager the epic looks good — approved
/pmanager we descoped the pagination task
/pmanager add a task to app-performance for connection pooling
```

"Done" claims are verified against the repo when the acceptance criteria are
checkable — the agent doesn't silently trust them.

**3. Status queries (write nothing):**

```text
/pmanager where are we on the performance work?
/pmanager what should we pick up next?
```

Recommendations respect task dependencies and priorities — a task whose
dependency is blocked won't be suggested.

## What it writes

Everything lives under `docs/pm/` in your repo, committed locally (scoped,
never pushed):

```text
docs/pm/
├── INDEX.md                  # one row per epic — the memory scanned every run
├── pmanager-memo.md          # product memo: goals, stakeholders, conventions
└── <epic-slug>/
    ├── epic.md               # why & what — problem, evidence, hypothesis, metrics, non-goals
    ├── plan.md               # how & when — milestones, risks, dependencies, MoSCoW, changelog
    └── tasks/
        ├── T01-<slug>.md     # self-contained INVEST tasks with binary acceptance criteria
        └── T02-<slug>.md
```

Later runs read `INDEX.md` and the memo first, so the agent remembers prior
epics, their outcomes, and what your product cares about. If the repo also
has `docs/sre-incidents/` (from the sre-agent skill), confirmed incident
root causes are reused as evidence.

## Worked example

You say:

```text
/pmanager we have a performance problem in our app — the orders page got
really slow for customers sometime in july. plan out the work to fix it.
```

**What the agent does:**

1. **Memory** — reads `docs/pm/INDEX.md` + memo (cold start here: none yet).
2. **Research (read-only)** — finds the N+1 query in `app/app.py:11`
   (one item-query per order), the missing index noted in `app/schema.sql`,
   and commit `91eb0bb` (2026-07-02) that removed pagination — the timing
   matches "slow since July". Every finding is recorded as `[source] fact`.
3. **Elicit** — asks only what the repo couldn't answer, e.g. "what latency
   counts as fixed?" and "does the mobile client pin the response shape?"
4. **Epic framing (gate)** — presents the summary and waits for your
   approval before anything else is written:

   > **Problem:** /orders returns every order for every user since
   > pagination was removed (91eb0bb), amplified by an N+1 query per order
   > against an unindexed table.
   > **Hypothesis:** restoring pagination and batching item queries returns
   > p95 /orders latency to <500 ms within 1 week of ship.
   > **Primary metric:** p95 /orders < 500 ms · **Guardrail:** error rate ≤ current.
   > **Non-goals:** storage-layer rewrite, reports redesign.
   > Approve, adjust, or send me back to research?

5. **On approval** — writes the spec and commits it (`docs(pm): spec
   orders-page-performance`):

   ```text
   docs/pm/orders-page-performance/
   ├── epic.md
   ├── plan.md          # M1 root cause confirmed → M2 query path bounded →
   │                    # M3 response bounded → M4 validated; risk register; MoSCoW
   └── tasks/
       ├── T01-benchmark-orders.md        # must, no deps — riskiest assumption first
       ├── T02-add-order-items-index.md   # must, depends-on [T01]
       ├── T03-batch-item-queries.md      # must, depends-on [T01]
       ├── T04-restore-pagination.md      # must, depends-on [T01]
       └── T06-regression-tests.md        # must, depends-on [T02, T03, T04]
   ```

   A task file is self-contained — an engineer or agent can pick it up cold:

   ```markdown
   ---
   id: T03
   epic: orders-page-performance
   milestone: M2
   title: Replace N+1 loop with a single join
   status: todo
   priority: must
   depends-on: [T01]
   estimate: M
   ---
   ## Context
   85% of /orders time is per-order item queries (../epic.md, evidence 3).
   ## Acceptance criteria
   - [ ] /orders issues O(1) queries per request (asserted in a test)
   - [ ] Response JSON unchanged (contract test passes)
   ## Out of scope
   - Index changes (T02), pagination (T04).
   ```

**A week later** you say:

```text
/pmanager T01 is done — profile is in docs/profile-results.txt, ~85% of
time is item queries. T02 is blocked waiting on DBA review. what's next?
```

The agent verifies T01's claim against the profile artifact, flips the
statuses (task frontmatter → plan table → INDEX row), records the blocker,
commits, and answers:

> Pick up **T04 — restore pagination**: it's the only unblocked must/should
> task (T03 depends on blocked T02). In parallel, chase the DBA review —
> the risk register's escalation trigger is "open > 3 days".

## Good to know

- **Nothing is written before you approve the epic** — except in
  non-interactive runs (nobody to ask), where the spec is written with the
  epic marked `draft` and your later "approved" flips it.
- **Research is read-only**; the only writes are `docs/pm/` and its scoped
  local commit. No pushes, no secrets/PII in the docs.
- **Too small for an epic?** The agent says so and offers a single task
  file instead of inflating a typo fix into a program of work.
- **Evidence honesty:** stated claims ("customers keep asking") are labeled
  distinctly from measured facts; unconfirmed metric targets are marked
  assumed, and low confidence usually turns into a discovery task (T01).

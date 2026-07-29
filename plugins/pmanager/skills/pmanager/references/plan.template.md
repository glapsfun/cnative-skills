# Plan template

`docs/pm/<slug>/plan.md`. The project-manager artifact: it answers *how and
when*, and carries the risk register. It is versioned — every revision after
first approval appends a changelog line, never silently rewrites history.

```markdown
---
epic: <slug>
status: draft | active | done | abandoned
updated: YYYY-MM-DD
---

# Plan — <epic title>

## Approach

3–8 sentences: the chosen approach, the main alternative considered, and why
this one won. Reasoning, not just the decision.

## Milestones

Milestones are verifiable state transitions, not dates. Each has exit
criteria that are binary — a reader can answer pass/fail without judgment.

### M1 — <state reached, e.g. "Root cause confirmed by profile">
Exit criteria:
- [ ] <binary criterion>
- [ ] <binary criterion>

### M2 — <state>
...

## Task breakdown & traceability

| Task | Title | Milestone | Priority | Depends on | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| T01 | Profile checkout hot paths | M1 | must | — | todo |
| T02 | Add index on orders.user_id | M2 | must | T01 | todo |

Every task maps to a milestone; every milestone serves the epic's primary
metric. A task that maps to nothing is a scope-creep flag — cut it or
re-frame the epic.

## Prioritization

MoSCoW over the tasks, **with reasoning** per non-obvious call (see
`prioritization.md`). Won't-haves listed here mirror the epic's non-goals.

- Must: ...
- Should: ...
- Could: ...
- Won't (this epic): ...

## Risk register

| Risk | Likelihood | Impact | Mitigation | Trigger / early signal |
| :--- | :--- | :--- | :--- | :--- |
| Index rebuild locks table in prod | med | high | build concurrently; off-peak window | migration takes >5 min in staging |

Revisit at every plan update — stale risk registers are worse than none.

## Dependencies

| Dependency | Kind | Owner | Status |
| :--- | :--- | :--- | :--- |
| staging env with prod-like data | internal | @infra | available |

## Definition of done (applies to every task)

- [ ] Acceptance criteria demonstrated
- [ ] Tests written/updated and passing
- [ ] Code reviewed
- [ ] Docs updated where behavior changed

## Validation plan

Two distinct checks — do not merge them:

- **Verification** (does the work meet the spec): how each milestone's exit
  criteria will be demonstrated.
- **Validation** (does it move the epic's metric): how and when the epic's
  primary + guardrail metrics get measured after ship, and who looks.

## Changelog

| Date | Change | Why |
| :--- | :--- | :--- |
| YYYY-MM-DD | Plan created | — |
```

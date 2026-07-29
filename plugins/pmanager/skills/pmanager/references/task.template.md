# Task template

`docs/pm/<slug>/tasks/TNN-<short-slug>.md` (e.g. `T01-profile-hot-paths.md`,
numbered in suggested execution order). The product-owner artifact: a
buildable, testable unit an agent or engineer can pick up **cold** — it must
not require re-deriving context from the epic or from conversation history.

## INVEST check before writing

- **Independent** — executable without waiting on undeclared work; real
  dependencies are declared in `depends-on`, not implied.
- **Negotiable** — describes the outcome and constraints, not every
  implementation keystroke.
- **Valuable** — traceable to a milestone (frontmatter proves it).
- **Estimable** — if you cannot size it, you don't understand it: split it
  or precede it with a spike task.
- **Small** — fits the estimate scale below (at most L ≈ 3 days). Anything
  you cannot honestly size at L or under → split.
- **Testable** — acceptance criteria are binary; no "improve", "clean up",
  or "make faster" without a number.

```markdown
---
id: T01
epic: <slug>
milestone: M1
title: <imperative one-liner>
status: todo | in-progress | blocked | done | descoped
priority: must | should | could
depends-on: []          # task ids, e.g. [T01, T02]
estimate: S | M | L     # S ≤ half day, M ≤ 2 days, L ≤ 3 days (larger: split)
owner: unassigned
updated: YYYY-MM-DD
---

# T01 — <Title>

## Context

One paragraph: why this task exists and what part of the epic it serves.
Link the epic (`../epic.md`) and cite the evidence lines that motivated it.

## What to do

Concrete, outcome-oriented steps or constraints. Name the files, services,
or interfaces involved when known. State the approach only where it is a
real constraint — leave room for the implementer elsewhere.

## Acceptance criteria

Binary, independently checkable:

- [ ] <criterion with a number, artifact, or observable state>
- [ ] <criterion>

## Out of scope

The adjacent work someone doing this task will be tempted to do — name it
so they don't. One line each.

## Notes

Evidence links, prior art, gotchas. Optional.
```

## Status transitions

`todo → in-progress → done`, with `blocked` reachable from any non-done
state (record the blocker in Notes and surface it to the user — a silent
blocked task is a lost task). `descoped` is terminal, set only through the
tracking flow when work is cut: the task moves to the plan's Won't list and
is excluded from INDEX task counts and next-task suggestions. Status changes
go through the tracking flow (`tracking.md`), which also updates the plan's
task table and INDEX.md.

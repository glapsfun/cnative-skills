# Prioritization

Two levels, two tools. At every level: record the **reasoning**, not just
the score — a number nobody can reconstruct persuades nobody later.

## Strategic filter first

Before scoring anything: does this work serve a stated business goal (memo
§ goals, or the answer elicited in Phase 3)? No alignment → the honest
options are "decline the epic" or "surface the mismatch to the user" — a
high RICE score cannot rescue misaligned work.

## Within an epic: MoSCoW over tasks

- **Must** — the epic's hypothesis cannot be tested / metric cannot move
  without it.
- **Should** — clearly serves the metric; the epic survives shipping
  without it.
- **Could** — cheap opportunistic value; first to cut under pressure.
- **Won't (this epic)** — named and written down in the plan; mirrors the
  epic's non-goals. The unwritten "won't" is the one that creeps back in.

Every Must claim is checkable: "the metric can't move without it" is either
true or the task isn't a Must. Write one line of reasoning per non-obvious
call in the plan's Prioritization section.

## Across epics: RICE, or impact/effort when data is thin

When the user asks "what should we do first" across multiple epics:

**RICE** = (Reach × Impact × Confidence) / Effort

- Reach: users/events per period, from evidence.
- Impact: 3 massive / 2 high / 1 medium / 0.5 low / 0.25 minimal.
- Confidence: 100% / 80% / 50% — **directly tied to the epic's Evidence
  table**: behavioral evidence supports 80–100%; stated-only evidence caps
  at 50%. Low confidence is a signal to run a discovery spike before
  committing, not a number to quietly inflate.
- Effort: person-days/weeks from the plans' estimates.

Inputs too unknown for RICE → fall back to a 2×2 impact/effort call and say
so; a defensible rough answer beats a precise fiction. Present the ranking
as a table with a reasoning line per epic; the user decides — pmanager
recommends, it does not decree.

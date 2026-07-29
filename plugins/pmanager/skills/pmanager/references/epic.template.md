# Epic template

`docs/pm/<slug>/epic.md`. The PM artifact: it answers *why this work exists
and what outcome it must produce*. Every factual claim carries its source.
Sections marked (required) must exist and be non-empty; write `none` or
`unknown` explicitly rather than omitting a section.

```markdown
---
id: <slug>
title: <one-line title>
type: bug | feature | tech-debt | initiative
status: draft | approved | in-progress | done | abandoned
business-goal: <the goal this serves, one line>
owner: <who owns the outcome — a person, or "unassigned">
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# <Title>

## Problem statement (required)

What is wrong or missing, for whom, and what it costs. 2–5 sentences,
solution-free — describe the problem space, not a fix.

## Evidence (required)

| Source | Finding | Kind |
| :--- | :--- | :--- |
| [src/db/orders.py:112] | N+1 query in order listing | behavioral |
| [git log] | pagination removed in a1b2c3 (2026-06-30) | behavioral |
| [user] | "customers complain checkout feels slow since July" | stated |

Kind is `behavioral` (measured/observed) or `stated` (claimed). Note
conflicts between the two explicitly.

**Confidence:** high | medium | low — with one line on what would raise it.

## Hypothesis (required)

We believe <change/approach> will <outcome> for <who>, measured by
<metric> reaching <target> within <window>.

## Business goal alignment

Why this matters to the business *now*; what happens if we don't do it.

## Stakeholders / affected users

Who is affected, who must be consulted, who signs off.

## Success metrics (required)

| Metric | Role | Current | Target | Window | Measured via |
| :--- | :--- | :--- | :--- | :--- | :--- |
| p95 checkout latency | primary | 3.1s | <800ms | 2 weeks post-ship | Grafana dashboard X |
| checkout error rate | guardrail | 0.2% | ≤0.2% | same | Prometheus |

One primary metric; at least one guardrail (a thing the fix must not break).

## Scope

What is in. Bullet list.

## Non-goals (required)

What is explicitly out, and in one clause each, why. This is the recorded
"no" — anything later proposed from this list needs a new decision, not a
silent scope change.

## Open questions

What remains unknown, who/what could answer it, and which task (if any)
exists to answer it.

## Related prior work

Links to related epics from `docs/pm/INDEX.md` and incidents from
`docs/sre-incidents/` with one line on what each taught us. `none` on a
cold start.
```

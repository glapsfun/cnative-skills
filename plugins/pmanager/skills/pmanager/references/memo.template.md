# Memo template

`docs/pm/pmanager-memo.md` — product context that outlives any single epic.
Created on the first Phase 6; updated every run. Metadata and reasoning
only — never secrets or PII.

```markdown
# PManager memo

_Last updated: YYYY-MM-DD_

## 1. Product context

What this product/repo is, who its users are, revenue/usage mechanism if
known. 3–6 lines, from evidence and elicitation — not speculation.

## 2. Business goals & north star

| Goal | Metric / north star | Source |
| :--- | :--- | :--- |
| Reduce checkout abandonment | conversion rate | [user, 2026-07-28] |

Epics cite these in their Business goal alignment section.

## 3. Stakeholders

| Who | Cares about | Consulted via |
| :--- | :--- | :--- |
| @jane (payments) | checkout reliability | review on payment-path epics |

## 4. Conventions & constraints

Durable facts that shape plans: release cadence, freeze windows, compliance
constraints, "all schema changes need DBA review", test/CI expectations.

## 5. Changelog

One line per run, newest first:

- YYYY-MM-DD — spec'd `app-performance`; learned checkout is the
  revenue-critical path.
```

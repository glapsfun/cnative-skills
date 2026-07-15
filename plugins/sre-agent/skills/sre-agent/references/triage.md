# Phase 3 Wave Triage

Splits Phase 3's *applicable* investigator set (per `SKILL.md`'s
per-investigator applicability rules — trace-backend + symptom shape,
EKS/GKE detection) into **Wave 1** (dispatched first) and **Wave 2**
(dispatched only if Wave 1 doesn't reach a high-confidence hypothesis).
This trades a small chance of a slower resolution (an extra wave) for a
much larger chance of a cheaper one (obvious-signature incidents never need
Wave 2) — driven by Phase 1's symptom class, the same canonical vocabulary
`references/incident-memory.md` uses for recall.

| Symptom class | Wave 1 | Wave 2 |
| :--- | :--- | :--- |
| crashloop | k8s, logs | metrics, changes |
| latency | metrics, traces | k8s, logs, changes |
| errors | logs, metrics | k8s, changes, traces |
| metrics (missing/broken) | k8s, metrics | logs, changes |
| oom | k8s, metrics | logs, changes |
| networking | k8s, metrics | logs, changes, traces |
| availability | k8s, metrics | logs, changes, traces |

## Rules that sit outside this table

- **EKS/GKE investigators always join Wave 1** when discovery recorded `EKS:
  detected` / `GKE: detected`, regardless of symptom class — this table only
  orders the *other* investigators; it never delays an already-applicable
  cloud investigator.
- **trace-analyst's applicability is unchanged** — it only ever enters the
  applicable set when a trace backend was discovered *and* the symptom is
  latency-, error-, or dependency-shaped. This table places it in whichever
  wave column it appears in *only when it is already applicable*; if it
  isn't applicable this run, its column entry is simply absent from the
  wave, same as today.
- If the applicable set is smaller than a table row implies (e.g. no trace
  backend, so `traces` was never applicable), the wave is whatever
  applicable investigators remain — never pad a wave with an investigator
  that didn't qualify.
- The `networking` and `availability` rows list `traces` in Wave 2 because
  those symptom classes are frequently *also* dependency-shaped (e.g. a
  downstream service or DNS dependency failing) — the applicability rule
  above is what actually gates it, not this table. If this run's specific
  incident isn't dependency-, latency-, or error-shaped, trace-analyst was
  never in the applicable set to begin with, so its cell here is simply
  never populated for that run.

## Naming note

"Wave" (not "tier") is deliberate: `investigators/k8s.md` already has its own,
unrelated "second-tier evidence" — an investigator-internal escalation to
nodes/NetworkPolicy/DNS when its own sweep is inconclusive. "Wave" keeps this
orchestrator-level investigator-*selection* concept distinct from that
investigator-*internal* one.

## Escalation rule (Phase 3)

`SKILL.md`'s Phase 3 steps own the full escalation procedure (the
provisional confidence assessment, the ledger fields, how it interacts with
mutation verification) — restated here only for the one edge case not
already covered there: Wave 2 is a no-op if the applicable set was already
fully covered by Wave 1 (nothing left to escalate to). In that case the
ledger's `Wave 2 investigators:` line should read "none — Wave 1 covered the
full applicable set" rather than dispatching nothing.

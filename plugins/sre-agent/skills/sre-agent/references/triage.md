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

## Naming note

"Wave" (not "tier") is deliberate: `investigators/k8s.md` already has its own,
unrelated "second-tier evidence" — an investigator-internal escalation to
nodes/NetworkPolicy/DNS when its own sweep is inconclusive. "Wave" keeps this
orchestrator-level investigator-*selection* concept distinct from that
investigator-*internal* one.

## Escalation rule (Phase 3)

After Wave 1's findings are merged into the ledger, check the ledger's
`Hypotheses:` confidence field:

- **No hypothesis at `high`** → dispatch Wave 2 (the remaining applicable
  investigators), merge its findings, then proceed to Phase 4.
- **A hypothesis already at `high`** → skip Wave 2. Record in the ledger's
  `Wave 2:` line which investigators were not run and why, e.g. "not
  dispatched — <hypothesis> reached high confidence."

Wave 2 is a no-op if the applicable set was already fully covered by Wave 1
(nothing left to escalate to) — note "Wave 2: none — Wave 1 covered the full
applicable set" rather than dispatching nothing.

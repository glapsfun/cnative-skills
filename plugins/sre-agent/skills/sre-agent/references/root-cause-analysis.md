# Root Cause Analysis

Phase 4 method. Inputs: the merged FACTS/ANOMALIES/GAPS blocks from all four
investigators. Outputs: ranked hypotheses and the expected-behavior criteria
that gate Phase 6. Interpretation happens here, in the main conversation —
investigators report facts only.

## Timeline first

Merge every timestamped fact into one ordered timeline before reasoning:

- first occurrence of each error signature (from `sre-logs-investigator`)
- alert `startsAt` times (from Alertmanager)
- metric inflection points (from the range queries)
- deploys, syncs, config revisions, image changes (from
  `sre-change-historian`)
- restart timestamps and event times (from `sre-k8s-investigator`)

The root cause almost always **precedes** the first symptom. Anything that
happened after the first symptom is a consequence, not a cause — a common
trap is chasing a secondary failure (e.g. a dependency alarming because the
broken service stopped calling it).

## Changes-before-symptoms heuristic

Any change — deploy, config, image, infrastructure, dependency version,
traffic pattern — that landed in the window before the first symptom is the
**leading hypothesis** until evidence contradicts it. "Nothing was deployed"
widens the window: check infra changes, certificate expiries, data growth
crossing a threshold, cron jobs, and upstream/downstream services' changes.

## Hypothesis ranking

Record every hypothesis in the ledger with:

- **Statement** — one sentence.
- **Mechanism** — how exactly it produces the observed symptoms. No
  mechanism, no hypothesis.
- **Supporting evidence** — ledger entry numbers.
- **Contradicting evidence** — ledger entry numbers; be honest.
- **Confidence** — high: mechanism + ≥2 independent evidence sources;
  medium: mechanism + 1 source; low: plausible but unverified.
- **Discriminating test** — the cheapest read-only check that would confirm
  or refute it.

Run discriminating tests (read-only) before proposing remediations —
raising a hypothesis from medium to high with one query is always cheaper
than remediating the wrong cause.

## Five whys, bounded

Iterate "why did that happen?" until you reach something actionable within
the team's control (a config value, a limit, a missing probe, a code path).
Stop when the next "why" leaves the technical domain (hiring, process,
vendor decisions) — record those as follow-up recommendations in the final
report, not as investigation branches.

## Common cloud-native failure chains

| Symptom | Typical chains | Discriminate by |
| :--- | :--- | :--- |
| OOMKilled | limit too low for legitimate load vs memory leak vs traffic spike | memory slope: leak climbs steadily regardless of traffic; spike correlates with RPS; chronic tightness OOMs at steady usage near limit |
| CrashLoopBackOff | config error vs bad image vs failing dependency vs liveness probe killing a slow-starting app | exit code (1/2 config or app, 137 kill), `--previous` logs, probe-failure events, whether the previous image version starts |
| Latency spike | CPU throttling/saturation vs downstream dependency vs retry storm vs GC pressure | throttling query; dependency latency vs own latency; request amplification (traffic up × errors up = retries); GC logs |
| Missing metrics | scrape target down vs ServiceMonitor label mismatch vs relabeling drop vs metric renamed vs cardinality limit | `up{}` for the target; ServiceMonitor selector vs Service labels; `/api/v1/targets` errors; app's `/metrics` endpoint directly |
| Pending pods | insufficient resources vs unsatisfiable affinity/taints vs unbound PVC vs quota | `kubectl describe pod` scheduling events name the failed predicate explicitly |
| Intermittent 5xx | one bad replica vs node-local issue vs race under load vs dependency flapping | error distribution per pod (`sum by (pod)`); per-node grouping; correlation with traffic level |

## Defining expected behavior

Turn "fixed" into measurable criteria before proposing any fix — this is the
TDD failing test. Each criterion needs a metric/observation, a threshold,
and a window:

```text
Expected behavior:
  - error rate < 1% of requests          (PromQL from prometheus-analysis.md)
  - p99 latency < 300ms                  (same source as the evidence query)
  - container restarts = 0               (kube_pod_container_status_restarts_total)
  - no new ERROR-class log signatures    (LogQL error hunt)
  - alert <name> resolved                (Alertmanager API)
Observation window: 15 minutes (default) — use ≥ 3× the symptom period for
intermittent issues.
```

Use the **same queries** that established the evidence, so before/after is
apples-to-apples. These criteria go in the ledger verbatim and become Phase
6's validation checklist.

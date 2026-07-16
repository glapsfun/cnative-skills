---
name: sre-agent
description: Use when the user reports an operational problem or incident — pods crashing or CrashLoopBackOff, latency spikes, rising error rates, missing/broken metrics, failing or stuck deployments, alerts firing, OOMKilled, service unreachable, node problems — or asks to investigate a production issue, find a root cause, plan a remediation, or write an incident report. Also invoked explicitly via /sre-agent.
---

# SRE Agent

Act as an experienced SRE assisting a human engineer. Drive incidents through a
TDD-inspired loop: collect evidence before conclusions, define expected behavior
before fixing, get explicit approval before changing anything, validate against
the expected behavior after changing, and iterate until resolved.

## Safety rules (non-negotiable)

1. **Read-only until approval.** Every command before Phase 6 must be
   non-mutating. Mutations happen only in this main conversation, only after the
   user explicitly selects a remediation option, and are scoped to exactly that
   option.
2. **Dry-run first.** Before every apply, run the ecosystem's preview
   (`kubectl diff` / `--dry-run=server`, `helm upgrade --dry-run`, `flux diff`,
   `terraform plan`, `pulumi preview`) and show the result before executing.
3. **Secrets: metadata only.** Names, ages, revision counts — never values.
   Never run commands that print secret data.
4. **Gentlest effective action.** Prefer `kubectl rollout restart` over deleting
   pods, scaling over deleting, config change over redeploy. State the blast
   radius before anything destructive.
5. **GitOps- and IaC-aware.** If the target is managed by Flux or Argo CD
   (check `managedFields`, labels, or the discovery output), direct the fix
   to the source repository. The same applies to cloud infrastructure
   managed by IaC — on EKS, Terraform/CDK/eksctl (node groups, IRSA roles,
   ALB controller config); on GKE, Terraform/Config Connector (node pools,
   Workload Identity bindings, load-balancer config) — check for IaC
   ownership signals (e.g. `eksctl.io/...` tags, Config Connector
   `cnrm.cloud.google.com/*` annotations) before proposing a fix. A direct
   cluster/console/CLI edit to anything GitOps- or IaC-managed needs
   explicit acknowledgment that reconciliation or the next `plan`/`apply`
   will revert it.
6. **Never guess.** Every claim in the ledger cites the command or query that
   produced it. If evidence is missing, say what is missing and how to get it.

## Reuse installed skills

For deep work in a sibling skill's domain, defer to it when installed
(check the available-skills list) rather than hand-rolling a weaker
equivalent. `references/sibling-skills.md` is the single source of truth
mapping situation → skill → concrete script/reference to use, with the
fallback for when the skill isn't installed. If a skill is missing, proceed
with your own knowledge and mention it can be installed from the
cnative-skills marketplace (Claude Code: `/plugin install
<name>@cnative-skills`; other agents: `npx skills add
glapsfun/cnative-skills --skill <name>`).

## The investigation ledger

Maintain one fenced markdown block, updated at every phase, posted in full
whenever it changes:

```text
INVESTIGATION LEDGER — <one-line problem statement>
Phase: <current phase>
Environment: <cluster/context, namespace, workload, GitOps manager, cloud>
Tools: <available> | Missing: <unavailable + what that blocks>
Wave 1 investigators: <list>
Wave 2 investigators: <list, or "not dispatched — <hypothesis> reached high confidence", or "none — Wave 1 covered the full applicable set">
Evidence:
  - [<source command/query>] <fact>            (each entry is a fact, not an interpretation)
Hypotheses:
  1. <hypothesis> — confidence <high/med/low> — supported by <evidence #s>
Expected behavior: <measurable criteria the fix must satisfy>
Options proposed: <summary + which was approved, or "awaiting approval">
Actions taken:
  - <timestamp> <command> → <result>
Validation: <criteria → pass/fail per criterion>
```

If `scripts/sre-snapshot.sh diff` reports any difference around a wave's
dispatch, insert this block into the ledger immediately and stop (see
Phase 3):

```text
⚠ SAFETY VIOLATION
  Wave: <1|2>  Investigators dispatched this wave: <list>
  Changed: <object> <field> <before-hash> → <after-hash>  (or: HEAD <sha> → <sha>)
```

A failed fix re-enters at Phase 3 with the ledger intact — record the failed
hypothesis, never rediscover from scratch.

## The loop

### Phase 0 — Bootstrap context

Before scoping, load prior knowledge. If `docs/sre-agent-memo.md` exists: read
it, run the **fast freshness check** in `references/project-memo.md` (contexts,
namespaces, service-map workloads, obs endpoints), and seed the ledger's
`Environment:` line from memo facts that pass — stamped `✓ verified <today>`.
The `Tools:` line records local CLI availability, which the memo does **not**
store — populate it in Phase 2 from `sre-env-discovery.sh`, never from the memo
(Safety rule 6 — never assume a tool exists). GitOps ownership is likewise not
trusted from the memo: re-verify the managing controller before any remediation
(Safety rule 5). Facts that fail the check are stamped `⚠ needs verification`
and carried into Phase 2 for real re-discovery; never delete a fact on a single
failed check. If the memo is absent, note "no memo — cold start" and continue.
Read `references/project-memo.md` for the schema, the freshness check, and the
update rules.

### Phase 1 — Understand and scope

Extract from the request: affected system/app, symptom class (metrics, logs,
deployment, networking, performance, availability), when it started, urgency.
Ask the user only what discovery cannot answer (e.g. which environment matters
if several are reachable). For Phase 3 wave triage and Phase 4 incident
recall, map the symptom onto the canonical signature classes in
`references/incident-memory.md` (the single source of truth for that
vocabulary).

### Phase 2 — Discover

On a **cold start** (no memo), run `scripts/sre-env-discovery.sh`, then
`scripts/sre-obs-discovery.sh` in full. On a **warm start**, run discovery
**only for what the memo did not cover or that failed the Phase 0 freshness
check** — do not re-discover facts the check already confirmed; that reuse is
the point of the memo. Always populate the `Tools:` line from
`sre-env-discovery.sh` (CLI availability is never taken from the memo).
Read `references/discovery.md` for interpreting the output and for manual
fallbacks. Record the environment map and an explicit
"Tools: available | Missing" line in the ledger. Never assume a tool exists.

The memo write-back does **not** happen here — it runs at end of run (Phase 6),
once the investigation has populated the service map. See Phase 6.

### Phase 3 — Collect evidence

The seven investigator playbooks live in `references/investigators/` (see
table). Each produces a findings block; merge every findings block into the
ledger. Two execution paths:

**Path A — subagent dispatch (preferred when available).** If your
environment provides named subagents matching the table (Claude Code plugin
install; Codex after `scripts/install-codex-agents.sh`), dispatch a wave's
investigators **concurrently** — a single message with one call per
investigator in that wave — each given: the problem statement, the
environment map, and the namespace/workload scope.

**Path B — inline execution (always works).** Otherwise, execute a wave's
playbooks yourself, sequentially: read `references/investigators/<file>`,
follow it exactly, and produce its findings block before starting the next.
Same evidence, same format — only slower.

| Subagent | Playbook | Collects |
| :--- | :--- | :--- |
| `sre-k8s-investigator` | `investigators/k8s.md` | Pod/deployment state, events, previous logs, resources vs limits, restarts, probes, rollout status; second-tier evidence (nodes, NetworkPolicy, DNS, storage) and mesh state when the standard sweep is inconclusive |
| `sre-metrics-analyst` | `investigators/metrics.md` | Golden signals + kube-state health from Prometheus, vs pre-incident baseline |
| `sre-logs-investigator` | `investigators/logs.md` | Error taxonomy from Loki or Elasticsearch/OpenSearch (kubectl logs fallback) across app + dependencies |
| `sre-change-historian` | `investigators/changes.md` | Timeline: git commits, PRs, CI runs, image tags, Helm/Flux/Argo history, config revisions |
| `sre-trace-analyst` | `investigators/traces.md` | Slowest/error traces, dependency path, span-level breakdown from Tempo/Jaeger — run only when a trace backend was discovered AND the symptom is latency-, error-, or dependency-shaped |
| `sre-eks-investigator` | `investigators/eks.md` | IRSA/IAM permission failures, VPC CNI health and IP exhaustion, node group/Fargate capacity, EKS control-plane logs (CloudWatch), ALB/EBS-EFS CSI and add-on health — run whenever discovery recorded `EKS: detected`, regardless of symptom shape |
| `sre-gke-investigator` | `investigators/gke.md` | Workload Identity (GSA/KSA) permission failures, VPC-native networking and IP exhaustion, node pool/Autopilot capacity, GKE control-plane logs (Cloud Logging), Ingress/backend-service health, Persistent Disk CSI, and add-on health — run whenever discovery recorded `GKE: detected`, regardless of symptom shape |

**Applicable set.** The rows above still gate membership exactly as before:
`sre-trace-analyst` only joins when a trace backend was discovered *and* the
symptom is latency-, error-, or dependency-shaped; `sre-eks-investigator`/
`sre-gke-investigator` join whenever EKS/GKE was detected, regardless of
symptom shape.

**Wave triage.** Read `references/triage.md` and map Phase 1's symptom class
onto its Wave 1/Wave 2 split of the applicable set. Triage only orders
within the applicable set — it never adds or removes membership.

For each wave, in order:

1. Snapshot state: `scripts/sre-snapshot.sh snapshot <namespace>
   [repo-path]` — pass `repo-path` whenever Phase 2 discovery identified a
   source/GitOps repository path (often simply the repo this session is
   invoked in); change-historian *receives* that path as an input, it does
   not discover it itself, so this is available starting Wave 1, not only
   once change-historian has run — keep the output.
2. Dispatch the wave's investigators (Path A concurrently, Path B
   sequentially) and merge their findings into the ledger.
3. Snapshot state again the same way, then run `scripts/sre-snapshot.sh diff
   <before> <after>`.
4. **The diff includes a `CLUSTER` line, or the after-snapshot's own
   `CLUSTER` line reads `unreachable`:** reachability changed between the
   two snapshots, or was unreachable for both (a same-value `CLUSTER
   unreachable` line in both snapshots produces no diff, so check the
   after-snapshot directly, not only the diff) — either way this wave's
   mutation check did not run to completion and its silence proves nothing.
   Record it under `Tools: Missing`, note in the ledger that this wave's
   mutation verification is degraded/inconclusive (see the
   degraded-environments table), and proceed to step 5/6 as if the diff
   were clean — but never claim the wave was verified.
5. **Diff reports any other difference:** stop — do not dispatch any
   further wave. Record a `⚠ SAFETY VIOLATION` block in the ledger (see the
   ledger format above), one line per ADDED/REMOVED/CHANGED entry the diff
   reported, naming the wave and its investigator set. Ask the user to
   acknowledge before Phase 3 resumes or the run is aborted — this is a
   safety-rule violation (Safety rule 1), not routine evidence.
6. **Diff is clean (or step 4 applied) and this was Wave 1:** make a
   lightweight, evidence-based provisional assessment of the leading
   hypothesis and its confidence from Wave 1's findings alone (same method
   as `references/root-cause-analysis.md`, at reduced depth — this does not
   replace Phase 4's full ranking once all evidence is in) and record it in
   the ledger's `Hypotheses:` field. No hypothesis at `high` → repeat steps
   1-5 for Wave 2 (the rest of the applicable set). A hypothesis already at
   `high` → skip Wave 2 and record why in the ledger's `Wave 2 investigators:`
   line.
7. **Diff is clean (or step 4 applied) and this was Wave 2 (or Wave 1 had
   nothing left to escalate to):** proceed to Phase 4, which finalizes the
   hypothesis ranking using all evidence collected across both waves.

For quick triage on either path, `scripts/sre-evidence.sh <namespace>
<workload>` produces a one-shot evidence pack.

### Phase 4 — Analyze and research

Read `references/root-cause-analysis.md`. Build the incident timeline, rank
hypotheses (changes-before-symptoms first), and record confidence per
hypothesis. Define **expected behavior** — measurable criteria the fix must
satisfy (e.g. "error rate < 1%, p99 < 300ms, restarts = 0 over 15 min").
These become Phase 6's validation checklist. Research fixes: repository
runbooks/docs first, then the pinned official docs listed in
`references/versioning-and-sources.md` via web fetch/search. Consult
`references/prometheus-analysis.md`, `references/logs-investigation.md`,
`references/grafana-discovery.md` as the evidence demands.

**Recall past incidents.** After ranking on this run's own evidence, consult
incident memory per `references/incident-memory.md`: if `docs/sre-incidents/INDEX.md`
exists, scan it and filter by the current signature (service + symptom class,
then error/metric fingerprint), open matching incident files, and confirm the
match against collected evidence. A confirmed match raises the matching
hypothesis's confidence (ledger: `supported by [incident <slug>]`) and adds its
validated fix as a **candidate** remediation for Phase 5 — re-validated through
the approval gate and Phase 6 dry-run, never auto-applied. No store, or no
match → note it and proceed.

### Phase 5 — Propose and approve (HARD GATE)

Read `references/remediation.md`. Present 2–4 options using its template
(description, steps, risk, pros, cons, expected impact, rollback plan) as a
structured question the user answers by picking one (use AskUserQuestion when
available). **Stop. Do not run any mutating command until the user
selects an option.** "Investigate more" is always a valid option to offer.

### Phase 6 — Apply, validate, iterate

Read `references/validation-and-reporting.md`. Dry-run → show → apply → watch
rollout. Then verify every expected-behavior criterion from Phase 4 with live
evidence (metrics queries, log checks, pod state). All pass → write the final
report (format in `references/validation-and-reporting.md`). Any fail →
record the failed hypothesis in the ledger and return to Phase 3. If
validation is impossible (e.g. no metrics access), report the fix as
**applied but unverified** — never claim resolution without evidence.

Optionally — when the fix warrants it and k6 is available — offer **load
validation** after passive validation passes: read
`references/load-validation.md`, derive thresholds from the ledger's
expected-behavior criteria, and present the run plan (target environment,
RPS, duration, blast radius) for **its own explicit approval**. Load
generation is mutation-class: never run it against production unless the
user explicitly says so.

**Write back the memo (end of run).** As the final step — whether the incident
resolved, is applied-but-unverified, or the run stops early — reconcile this
run's *verified* findings into `docs/sre-agent-memo.md` per the update rules in
`references/project-memo.md`: add newly discovered structure and any service
investigated this run to the service map (with its GitOps manager and image
tag), update changed rows and append a §4 Changelog line, mark
failed-verification facts `needs verification` (never hard-delete on a single
miss), append one §5 Discovery-history line, refresh `_Last verified:_`, then
write and commit the memo **locally, scoped to the memo path with an inline
message** (never a bare `git commit`; no push; no co-author line). On a cold
start, create it from `references/project-memo.template.md`. Writing the memo is
a local-documentation update, not a target mutation — it stores metadata and
pointers only, never secret values.

**Capture the incident (validated resolutions only).** If — and only if — a
remediation was applied and every expected-behavior criterion passed, record the
incident per `references/incident-memory.md`: write
`docs/sre-incidents/<YYYY-MM-DD>-<slug>.md` from `references/incident.template.md`
(symptom, confirmed root cause, decisive evidence with sources, validated fix +
rollback, validation results, ruled-out hypotheses, links), prepend a row to
`docs/sre-incidents/INDEX.md`, and commit locally scoped to the incident paths
with an inline message (never a bare `git commit`; no push; no co-author line).
Applied-but-unverified, abandoned, or investigate-only runs capture nothing.
Metadata and pointers only — never secret values.

## Degraded environments (the normal case)

| Missing | Fallback |
| :--- | :--- |
| Cluster access | Analyze repo manifests/docs; state the limitation |
| Prometheus | `kubectl top` + events + restart counts |
| Loki | Elasticsearch/OpenSearch (see `references/elk-investigation.md`), else `kubectl logs` (current + `--previous`) |
| Grafana | Skip dashboard discovery; note it |
| Trace backend (Tempo/Jaeger) | Skip the trace path; note latency RCA is metrics/logs-only |
| Mesh CLIs (istioctl/linkerd) | kubectl-only mesh evidence: CRDs, PeerAuthentication, sidecar logs |
| k6 | Passive validation only; offer the script + manual run instructions |
| Web access | Pinned knowledge in references, with staleness warning |
| GitOps tooling | git history + manifest inspection |
| `aws` CLI missing/unauthenticated (EKS detected) | kubectl-only EKS evidence: aws-node health, node labels, ServiceAccount role-arn annotations, Fargate pod annotations; control-plane logs/ASG/ALB/IAM detail recorded under GAPS |
| `gcloud` CLI missing/unauthenticated (GKE detected) | kubectl-only GKE evidence: node labels, KSA Workload Identity annotations, Dataplane V2/Calico NetworkPolicy objects; control-plane logs/node-pool/backend-service/add-on detail recorded under GAPS |
| `sre-snapshot.sh` fails, or its `CLUSTER` line reads `unreachable` | Record under `Tools: Missing`; per Phase 3 step 4, treat as a degraded/inconclusive mutation check for that wave (not a violation) and note the gap in the ledger — proceed on the investigator's own read-only instructions rather than blocking the investigation |

Always record missing capability in the ledger; never silently skip.

## Reference files — read when the phase goes deeper

| File | Read when |
| :--- | :--- |
| `references/discovery.md` | Phase 2 — interpreting discovery output, manual endpoint hunting, port-forward patterns |
| `references/project-memo.md` | Phase 0 bootstrap + Phase 6 end-of-run write-back — memo schema, fast freshness check, update rules, changelog/discovery-history conventions |
| `references/incident-memory.md` | Phase 4 recall + Phase 6 capture — incident signature, index/recall recipe, capture rules |
| `references/investigators/*.md` | Phase 3 — the seven investigator playbooks; source of truth for the subagents, executed inline on Path B |
| `references/triage.md` | Phase 3 — symptom-class → Wave 1/Wave 2 investigator split, escalation rule |
| `references/prometheus-analysis.md` | Querying Prometheus: golden signals, kube-state, baselines, burn rates |
| `references/logs-investigation.md` | LogQL patterns, log-source selection, error taxonomy |
| `references/grafana-discovery.md` | Finding dashboards/datasources/alert rules via Grafana API |
| `references/tracing-investigation.md` | TraceQL/Jaeger recipes, reading traces, trace↔log↔metric correlation |
| `references/elk-investigation.md` | Elasticsearch/OpenSearch index discovery, query DSL error hunting, error trends |
| `references/k8s-deep-evidence.md` | Second-tier Kubernetes evidence: nodes, NetworkPolicy, DNS, storage/CSI, control plane |
| `references/mesh-investigation.md` | Istio/Linkerd detection, proxy evidence, mTLS/traffic-policy failure chains |
| `references/load-validation.md` | Phase 6 optional k6 load validation: thresholds from expected behavior, run plans, guardrails |
| `references/root-cause-analysis.md` | Phase 4 — correlation method, hypothesis ranking, timeline construction |
| `references/sibling-skills.md` | Phase 3 evidence-gathering and Phase 5 remediation — which sibling skill's script/reference to defer to for a situation, and the fallback when it isn't installed |
| `references/remediation.md` | Phase 5 — option template, risk classification, safe-change rules |
| `references/terraform-remediation.md` | Phase 4 (locate the resource) and Phase 5/6 (construct the fix, classify the plan, safe apply/rollback) — remediation target is Terraform-managed infrastructure |
| `references/validation-and-reporting.md` | Phase 6 — verification checklist, final report format |
| `references/versioning-and-sources.md` | Which official docs to trust for runtime research + refresh checklist |

## Scripts

All read-only, safe against live clusters, `-h/--help`, degrade gracefully:

- `scripts/sre-env-discovery.sh` — CLI inventory, kube context/namespaces, GitOps detection, cloud CLIs.
- `scripts/sre-obs-discovery.sh` — locate Prometheus/Alertmanager/Grafana/Loki/Mimir/Tempo/Jaeger/Elasticsearch endpoints and detect service mesh and k6 (never prints secret values).
- `scripts/sre-evidence.sh <namespace> <workload>` — one-shot Kubernetes evidence pack.
- `scripts/sre-snapshot.sh` — Phase 3 mutation verification: snapshot/diff spec-hash fingerprints of namespace-scoped k8s objects (and git HEAD/porcelain for a target repo) around each wave's investigator dispatch.
- `scripts/terraform-plan-check.sh <tf-dir>` — Phase 5/6 Terraform remediation: classifies `terraform plan` output into no-op/create/update/delete/replace counts and flags any destroy/replace before apply.
- `scripts/install-codex-agents.sh` — copy the bundled Codex subagent TOMLs (`agents/codex/`) into `${CODEX_HOME:-~/.codex}/agents/` so Codex can run Phase 3 Path A.

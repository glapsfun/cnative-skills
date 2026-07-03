# sre-agent

Agentic SRE orchestrator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and Codex — an assistant that helps human SRE engineers investigate and resolve operational incidents.

## Main goal

Behave like an experienced SRE sitting next to you during an incident. The
agent does **not** replace the human: it drives the investigation — discovers
the environment, collects evidence, finds the most probable root cause,
researches fixes, and proposes remediation options — while **you stay in
control of every change**. Nothing is mutated without your explicit approval,
every apply is preceded by a dry-run, and every option comes with a rollback
plan.

The agent follows a TDD-inspired loop:

1. **Understand** the problem and its scope.
2. **Discover** the environment: cluster, tools, GitOps manager, observability endpoints.
3. **Collect evidence** in parallel — Kubernetes state, Prometheus metrics, Loki or Elasticsearch/OpenSearch logs, Tempo/Jaeger traces, service-mesh state, and recent changes (git, CI/CD, Helm, Flux/Argo) — via five read-only investigator subagents.
4. **Analyze**: build a timeline, rank root-cause hypotheses, and define *expected behavior* — the measurable criteria a fix must satisfy (the "failing test").
5. **Propose** 2–4 remediation options (description, steps, risk, pros/cons, impact, rollback) and **wait for your approval** — a hard gate.
6. **Apply, validate, iterate**: dry-run → apply → verify every expected-behavior criterion with live evidence — optionally under representative k6 load, behind its own approval gate. Pass → final incident report. Fail → back to step 3 with everything learned retained.

## Installation

Claude Code (after adding the marketplace once with
`/plugin marketplace add glapsfun/cnative-skills`):

```text
/plugin install sre-agent@cnative-skills
```

Codex:

```bash
npx skills add glapsfun/cnative-skills --skill sre-agent --agent codex --global -y
```

## How to use

Start an investigation explicitly with the slash command:

```text
/sre-agent my payments service is crash-looping in prod, namespace payments
```

Or just describe the problem — the skill auto-triggers on incident-shaped
requests:

```text
p99 latency on the checkout API went from 200ms to 3s an hour ago. Nothing was deployed.
Our application metrics disappeared from Grafana yesterday.
Pods in namespace search are OOMKilled every few hours.
```

The agent then walks the loop above, keeping a visible **investigation
ledger** (environment, evidence with the command that produced each fact,
hypotheses with confidence, actions, validation results) updated at every
phase. When it reaches the approval gate it presents the options and stops —
pick one, ask for more evidence, or reject them all.

After resolution you get a final incident report (summary, impact, timeline,
root cause, actions, validation, rollback info, follow-ups) that you can save
to your repo.

## What's inside

| Component | Purpose |
| :--- | :--- |
| `skills/sre-agent/SKILL.md` | The orchestrator: loop, phase gates, safety rules, investigation ledger |
| `agents/` — `sre-k8s-investigator`, `sre-metrics-analyst`, `sre-logs-investigator`, `sre-change-historian`, `sre-trace-analyst` | Read-only subagents dispatched in parallel for evidence collection |
| `skills/sre-agent/references/` | Deep knowledge loaded on demand: discovery, PromQL (golden signals, kube-state, burn rates), LogQL and error taxonomy, Elasticsearch/OpenSearch query DSL, TraceQL/Jaeger tracing, deep Kubernetes evidence (nodes, NetworkPolicy, DNS, storage), service mesh (Istio/Linkerd), Grafana API discovery, root-cause analysis method, remediation templates, validation checklist and report format, k6 load validation, pinned official sources |
| `skills/sre-agent/scripts/` | Read-only helpers: `sre-env-discovery.sh` (tools, cluster, GitOps, cloud), `sre-obs-discovery.sh` (Prometheus/Alertmanager/Grafana/Loki/Mimir/Tempo/Jaeger/Elasticsearch endpoints, service-mesh and k6 detection), `sre-evidence.sh <ns> <workload>` (one-shot evidence pack) |
| `commands/sre-agent.md` | The `/sre-agent <problem>` entry point |

## Safety model

- **Read-only until approval** — investigation never mutates; only the main
  conversation applies changes, only after you select an option.
- **Dry-run first** — `kubectl diff`/`--dry-run=server`, `helm --dry-run`,
  `flux diff`, `terraform plan`, `pulumi preview` before every apply.
- **Secrets: metadata only** — names, ages, revisions; never values.
- **GitOps-aware** — fixes to Flux/Argo-managed workloads are directed to the
  source repository, not hand-edited into the cluster.
- **Gentlest effective action** — restart over delete, scale over replace;
  blast radius stated before anything destructive.

## Degraded environments

Missing tooling is the normal case, not an error. No Prometheus → `kubectl
top` + events; no Loki → `kubectl logs`; no cluster access at all → static
analysis of repo manifests with the limitation stated. Every gap is recorded
in the ledger; the agent never claims a fix is verified without evidence.

## Works best with

Install alongside the other plugins from this marketplace — the orchestrator
defers to them for deep work when they are available:
[`kubernetes-operator`](../kubernetes-operator/), [`helm`](../helm/),
[`fluxcd`](../fluxcd/), [`argocd`](../argocd/).

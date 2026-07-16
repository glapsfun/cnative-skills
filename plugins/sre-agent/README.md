# sre-agent

Agentic SRE orchestrator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Codex, Gemini CLI, Copilot CLI, and any agent that supports the [Agent Skills](https://agentskills.io) standard — an assistant that helps human SRE engineers investigate and resolve operational incidents.

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
3. **Collect evidence** — Kubernetes state, Prometheus metrics, Loki or Elasticsearch/OpenSearch logs, Tempo/Jaeger traces, service-mesh state, recent changes (git, CI/CD, Helm, Flux/Argo), and cloud-specific evidence on AWS EKS (IRSA/VPC CNI, node group/Fargate capacity, control-plane logs, ALB/CSI/add-ons) and GCP GKE (Workload Identity/VPC-native networking, node pool/Autopilot capacity, Cloud Logging control-plane logs, Ingress/CSI/add-ons) — via seven read-only investigator playbooks, triaged into a cheaper first wave and an escalation wave by symptom class, dispatched in parallel as subagents where the host supports them (otherwise executed inline sequentially), with each wave's dispatch mechanically verified read-only via a live state snapshot/diff.
4. **Analyze**: build a timeline, rank root-cause hypotheses, and define *expected behavior* — the measurable criteria a fix must satisfy (the "failing test").
5. **Propose** 2–4 remediation options (description, steps, risk, pros/cons, impact, rollback) and **wait for your approval** — a hard gate.
6. **Apply, validate, iterate**: dry-run → apply → verify every expected-behavior criterion with live evidence — optionally under representative k6 load, behind its own approval gate. Pass → final incident report. Fail → back to step 3 with everything learned retained.

## Installation

The full 6-phase investigation works on every target. The difference is only
*how* Phase 3 evidence collection runs: with subagents (parallel, faster) or
inline (sequential, same evidence and format).

| Target | Install | Phase 3 |
| :--- | :--- | :--- |
| **Claude Code** | `/plugin marketplace add glapsfun/cnative-skills` (once), then `/plugin install sre-agent@cnative-skills` | Parallel subagents + `/sre-agent` command |
| **Codex** | `npx skills add glapsfun/cnative-skills --skill sre-agent --agent codex --global -y`, then run the skill's bundled `scripts/install-codex-agents.sh` (installs to `~/.codex/agents/`; with `--project`, run it from your project directory — the target resolves against your cwd) | Parallel subagents (TOML, bundled). Skill alone = full investigation, sequential |
| **Gemini CLI** | `npx skills add glapsfun/cnative-skills --skill sre-agent --agent gemini-cli --global -y` | Full investigation, sequential |
| **Copilot CLI** | `npx skills add glapsfun/cnative-skills --skill sre-agent --agent copilot --global -y` (also picks up `.claude/skills/` installs) | Full investigation, sequential |

For Claude Code always use `/plugin install` — it additionally registers the
`/sre-agent` command and the seven subagents. After updating the skill on
Codex, re-run `install-codex-agents.sh` so the subagents stay in sync with
the playbooks.

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
The checkout service is slow and we run Tempo — find which downstream call is eating the time.
Our logs live in OpenSearch, no Loki — what errors is the orders app throwing since 09:00?
The fix is applied and metrics look good — verify it under load before we close the incident.
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
| `skills/sre-agent/references/investigators/` | The seven investigator playbooks (k8s, metrics, logs, changes, traces, eks, gke) — single source of truth; executed inline when subagents are unavailable |
| `agents/` — `sre-k8s-investigator`, `sre-metrics-analyst`, `sre-logs-investigator`, `sre-change-historian`, `sre-trace-analyst`, `sre-eks-investigator`, `sre-gke-investigator` | Read-only Claude Code subagents dispatched in parallel for evidence collection — generated from `references/investigators/` by `scripts/gen-sre-agent-artifacts.sh` |
| `skills/sre-agent/agents/codex/` | The same seven subagents in Codex TOML format (generated); installed by `install-codex-agents.sh` |
| `skills/sre-agent/references/` | Deep knowledge loaded on demand: discovery, PromQL (golden signals, kube-state, burn rates), LogQL and error taxonomy, Elasticsearch/OpenSearch query DSL, TraceQL/Jaeger tracing, deep Kubernetes evidence (nodes, NetworkPolicy, DNS, storage), service mesh (Istio/Linkerd), Grafana API discovery, root-cause analysis method, remediation templates, Terraform remediation (locating IaC-managed resources, safe plan reading, plan-classified apply/rollback), validation checklist and report format, k6 load validation, sibling-skill deference (argocd/fluxcd/helm/bash-scripting/kubernetes-operator/karpenter), pinned official sources |
| `skills/sre-agent/scripts/` | Read-only helpers: `sre-env-discovery.sh` (tools, cluster, GitOps, cloud), `sre-obs-discovery.sh` (Prometheus/Alertmanager/Grafana/Loki/Mimir/Tempo/Jaeger/Elasticsearch endpoints, service-mesh and k6 detection), `sre-evidence.sh <ns> <workload>` (one-shot evidence pack), `sre-snapshot.sh` (Phase 3 mutation verification: snapshot/diff spec-hash fingerprints around each wave's dispatch), `terraform-plan-check.sh <tf-dir>` (Phase 5/6 Terraform plan classification: no-op/create/update/delete/replace counts, flags any destroy/replace), `install-codex-agents.sh` (Codex subagent install) |
| `commands/sre-agent.md` | The `/sre-agent <problem>` entry point (Claude Code) |

## Safety model

- **Read-only until approval** — investigation never mutates; only the main
  conversation applies changes, only after you select an option.
- **Dry-run first** — `kubectl diff`/`--dry-run=server`, `helm --dry-run`,
  `flux diff`, `terraform plan`, `pulumi preview` before every apply.
- **Secrets: metadata only** — names, ages, revisions; never values.
- **GitOps- and IaC-aware** — fixes to Flux/Argo-managed workloads, and to
  Terraform/CDK/eksctl-managed EKS infrastructure (node groups, IRSA roles,
  ALB config), are directed to the source repository/IaC, not hand-edited
  directly.
- **Gentlest effective action** — restart over delete, scale over replace;
  blast radius stated before anything destructive.
- **Load generation is mutation-class** — the optional k6 validation step has
  its own approval gate, states target environment/RPS/duration/blast radius
  up front, and never targets production unless you explicitly say so.

## Degraded environments

Missing tooling is the normal case, not an error. Every capability has a
fallback: no Prometheus → `kubectl top` + events; no Loki →
Elasticsearch/OpenSearch, else `kubectl logs`; no trace backend → latency
RCA proceeds metrics/logs-only; mesh present but no `istioctl`/`linkerd`
CLI → kubectl-only mesh evidence; no k6 → passive validation plus a script
you can run yourself; no cluster access at all → static analysis of repo
manifests with the limitation stated. Every gap is recorded in the ledger;
the agent never claims a fix is verified without evidence.

## Works best with

Install alongside the other plugins from this marketplace — the orchestrator
defers to them for deep work when they are available:
[`kubernetes-operator`](../kubernetes-operator/), [`helm`](../helm/),
[`fluxcd`](../fluxcd/), [`argocd`](../argocd/), [`karpenter`](../karpenter/).

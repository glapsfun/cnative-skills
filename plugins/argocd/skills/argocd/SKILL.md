---
name: argocd
description: Argo CD GitOps guidance for Kubernetes. Use when Codex needs to install or upgrade Argo CD, design GitOps architecture, author or review Application, AppProject, ApplicationSet, repository, project, RBAC, SSO, Dex, notification, Helm, Kustomize, multi-source, sync wave, hook, ignoreDifferences, or app-of-apps configuration, operate argocd CLI workflows, secure multi-tenant Argo CD, or troubleshoot sync, health, drift, repo, cluster, auth, and ApplicationSet issues. Trigger on Argo CD YAML, argocd CLI output, sync status, OutOfSync, Degraded, Progressing, Missing, InvalidSpecError, repo-server, application-controller, AppProject, ApplicationSet, Sealed Secrets, External Secrets, or GitOps CD questions where Argo CD is the tool.
---

# Argo CD

Use this skill to work with Argo CD as a Kubernetes GitOps controller. Treat Argo CD behavior as version-sensitive: check the target cluster, chart, operator, or manifest version before giving field-level or upgrade-sensitive advice.

## First Step

Run or adapt the version helper before making version-sensitive operational claims:

```bash
bash scripts/argocd-version-check.sh
```

For troubleshooting, run or adapt the diagnostics helper. Use broad mode first when the failing app is unknown, or app mode when the user gives an Application name:

```bash
bash scripts/argocd-diagnostics.sh
bash scripts/argocd-diagnostics.sh --app <app-name> --dest-namespace <namespace>
```

If scripts are unavailable, collect the minimum target context manually:

```bash
argocd version
kubectl get applications.argoproj.io -A
kubectl get appprojects.argoproj.io -n argocd
kubectl get applicationsets.argoproj.io -n argocd
kubectl -n argocd get deploy,sts,po,cm,secret
```

If the user provides an Argo CD version, Helm chart version, operator version, controller image tag, Application YAML, CLI output, or cluster events, use that as the target context. If no version is known, say which assumptions your answer uses and recommend verifying against the live cluster or repo.

## Task Routing

- **Concepts, architecture, or install planning**: read `references/01-installation-and-concepts.md`; distinguish quickstart installs from production HA and GitOps-managed installs.
- **Applications, AppProjects, ApplicationSets, hooks, sync waves, app-of-apps, Helm, Kustomize, multi-source, or sync options**: read `references/02-crds-and-configuration.md`; verify exact fields against the live CRD or official docs when accuracy matters.
- **CLI workflows, CI/CD usage, deletion, rollback, diffs, or sync commands**: read `references/03-cli-reference-and-best-practices.md`; provide declarative YAML equivalents when the command changes persistent state.
- **Security, RBAC, SSO, Dex, OIDC, secrets, notifications, tenant isolation, or audit concerns**: read `references/04-security-rbac-sso.md`; default to least privilege and explicit project boundaries.
- **Troubleshooting, HA, performance, metrics, upgrades, repo issues, controller logs, stuck operations, OutOfSync, Degraded, Progressing, Missing, or Unknown health**: read `references/05-troubleshooting-and-advanced.md`; gather live evidence before proposing fixes.
- **Research refresh or source verification**: use `../../../../docs/research-argocd.md` from this skill directory when present, then prefer official Argo CD documentation for details that may have changed.
- **Official documentation discovery**: run `bash scripts/argocd-doc-discover.sh` when updating this skill or checking upstream doc paths.

## Operating Rules

Prefer declarative Git changes over UI or CLI mutations for persistent fixes. When the cluster is GitOps-managed, point edits to the source repository because UI or CLI changes can be overwritten.

Read live state before mutating it:

```bash
argocd app get <app> --show-operation
argocd app diff <app>
kubectl describe application <app> -n argocd
kubectl get events -n <destination-namespace> --sort-by=.lastTimestamp
```

Separate sync status from workload health. An app can be `Synced` and still be `Degraded` because Pods, Jobs, hooks, or custom health checks are failing.

Minimize blast radius. Use `argocd app diff`, `argocd app sync --dry-run`, resource-scoped syncs, and `argocd app terminate-op` before broad sync, prune, replace, force, or deletion commands.

Do not invent CRD fields. For field-level questions, check `kubectl explain`, the live CRD, official docs, or the relevant reference file before giving YAML.

Do not put secrets directly in Application manifests or Git. Prefer External Secrets, Sealed Secrets, SOPS, a supported plugin, or secret references appropriate to the user's environment.

Avoid default-wide permissions. Use AppProjects to constrain source repositories, destinations, namespaces, cluster-scoped resources, and project roles. Avoid broad `*/*` grants unless the user explicitly accepts the risk.

Treat ApplicationSet templating as a privilege boundary. Review generators, selectors, templated project fields, and repository write access before recommending broad automation.

For upgrades, inspect release notes, CRD changes, chart/operator compatibility, and backup/export strategy before changing versions.

## Script Helpers

Use bundled scripts for repeatable read-only evidence gathering:

| Script | Use |
|---|---|
| `scripts/argocd-version-check.sh` | Check latest upstream release, local CLI version, live controller images, and CRD presence |
| `scripts/argocd-diagnostics.sh` | Collect control-plane inventory or app-specific status, diff, resources, Application CR, events, and optional logs |
| `scripts/argocd-doc-discover.sh` | Discover official upstream docs, examples, manifests, and chart files |

Keep scripts read-only. Do not add sync, delete, patch, apply, terminate, or force operations to diagnostics helpers.

## Quick Diagnostics

```bash
# Full app status, health, sync, conditions, and last operation
argocd app get <app-name> --show-operation

# See Git-vs-live drift
argocd app diff <app-name>

# Refresh Git and cluster comparison
argocd app get <app-name> --refresh
argocd app get <app-name> --hard-refresh

# List managed resources
argocd app resources <app-name>

# Sync one resource instead of the entire app
argocd app sync <app-name> --resource apps:Deployment:<name> --dry-run

# Stop a stuck operation before retrying
argocd app terminate-op <app-name>

# Controller-side evidence
kubectl -n argocd logs deploy/argocd-application-controller
kubectl -n argocd logs deploy/argocd-repo-server
```

## Status Triage

| Symptom | Start with | Common causes |
|---|---|---|
| `OutOfSync` after sync | `argocd app diff <app>` | Mutating webhook, controller-managed field, Helm random data, dropped unknown fields |
| `Synced` but `Degraded` | `argocd app get <app> --show-operation` and workload events | CrashLoopBackOff, readiness failure, failed hook, custom health check |
| `Progressing` forever | `argocd app resources <app>` and destination namespace Pods/Jobs | rollout blocked, hook pending, dependency not ready |
| `Missing` | resource tree and pruning history | resource never applied, was pruned, namespace mismatch |
| Sync failed | operation state and Application conditions | RBAC, quota, invalid YAML, missing CRD, hook failure |
| Repo or comparison error | `argocd repo list` and repo-server logs | expired credentials, SSH known_hosts, GitLab `.git` URL, manifest generation failure |
| Auth or CLI failures | `argocd context`, server logs, RBAC validation | wrong server mode, gRPC-web proxy, SSO/RBAC mismatch |

## Core Patterns

### Minimal Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/my-config.git
    targetRevision: HEAD
    path: apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 2m
```

### AppProject Boundary

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform
  namespace: argocd
spec:
  sourceRepos:
    - https://github.com/my-org/platform-config.git
  destinations:
    - server: https://kubernetes.default.svc
      namespace: platform-*
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
  roles:
    - name: deployer
      policies:
        - p, proj:platform:deployer, applications, sync, platform/*, allow
      groups:
        - my-org:platform-team
```

### ignoreDifferences for Controller Mutations

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
    - group: "*"
      kind: "*"
      managedFieldsManagers:
        - kube-controller-manager
  syncPolicy:
    syncOptions:
      - RespectIgnoreDifferences=true
```

## Reference Files

Load only the reference needed for the task:

| File | Contents |
|---|---|
| `references/01-installation-and-concepts.md` | Architecture, install methods, HA vs non-HA, ingress, getting started |
| `references/02-crds-and-configuration.md` | Application, AppProject, ApplicationSet, source types, sync options, hooks |
| `references/03-cli-reference-and-best-practices.md` | CLI reference, CI/CD patterns, sync waves, app deletion, diffs |
| `references/04-security-rbac-sso.md` | RBAC, SSO, Dex/OIDC, secrets, notifications, multi-tenancy |
| `references/05-troubleshooting-and-advanced.md` | Troubleshooting, HA, metrics, performance, upgrades, advanced patterns |

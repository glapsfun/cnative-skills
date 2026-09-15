---
plugin: kubernetes-operator
upstream_name: Kubernetes
version_source: github-release
upstream_repo: kubernetes/kubernetes
upstream_url:
upstream_key:
extra_repos: [helm/helm]
version_match: minor
verified_version: v1.36.0
verified_date: 2026-06-12
last_upgrade: never
plugin_version: 1.0.1
check_interval_days: 90
---

# kubernetes-operator — upgrade memo

Ledger entry created 2026-09-14. Docs-baselined: `verified_version` tracks the Kubernetes minor (compare with `version_match: minor`); the Helm docs baseline (v4.2.0) is a second axis recorded in the watch list. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Releases: <https://github.com/kubernetes/kubernetes/releases>
- Changelogs: <https://github.com/kubernetes/kubernetes/tree/master/CHANGELOG>
- Docs: <https://kubernetes.io/docs/>
- Deprecation guide: <https://kubernetes.io/docs/reference/using-api/deprecation-guide/>
- kubectl reference: <https://kubernetes.io/docs/reference/kubectl/>
- Release announcements (leads): <https://kubernetes.io/blog/>
- Helm docs (second axis): <https://helm.sh/docs/>

## Skill map

- `SKILL.md` — 84 lines
- `references/api-machinery.md` — API Machinery, RBAC & Object Model
- `references/gitops.md` — GitOps & Kustomize
- `references/helm.md` — Helm
- `references/kubectl.md` — kubectl Reference
- `references/networking-storage.md` — Networking, Storage & Configuration
- `references/security.md` — Security Hardening
- `references/versioning-and-sources.md` — Versioning & Official Sources
- `references/workloads-scheduling.md` — Workloads, Pod Lifecycle & Scheduling
- `scripts/k8s-context-check.sh` — (no header comment)
- `scripts/k8s-diagnose.sh` — (no header comment)
- `scripts/k8s-manifest-lint.sh` — (no header comment)
- `scripts/k8s-net-debug.sh` — (no header comment)
- `scripts/k8s-rbac-check.sh` — (no header comment)
- `evals/evals.json` — 9 evals

## Watch list

- `references/versioning-and-sources.md` — "Snapshot date: 2026-06-12", "Kubernetes docs baseline: v1.36", "Helm docs baseline: v4.2.0".
- `references/api-machinery.md` — API versions and feature-gate graduations.
- `references/security.md` — Pod Security Standards profile details.
- `references/kubectl.md` — `kubectl debug --profile` and other flags added per minor.
- `references/helm.md`, `references/gitops.md` — overlap with the `helm`, `fluxcd`, `argocd` plugins; keep consistent (cross-plugin open items).

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

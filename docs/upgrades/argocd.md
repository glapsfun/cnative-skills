---
plugin: argocd
upstream_name: Argo CD
version_source: github-release
upstream_repo: argoproj/argo-cd
upstream_url:
upstream_key:
extra_repos: [argoproj/argo-helm]
version_match: exact
verified_version: unknown
verified_proxy: true
verified_date: 2026-06-28
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# argocd — upgrade memo

Ledger entry created 2026-09-14. Content implies a v3.4-era baseline (support matrix stops at v3.4 / Kubernetes 1.35); the version-check script has no baseline constant. Establish on the first update run. `verified_date` is the plugin's last content commit (proxy) — no verification run yet.

## Sources

- Releases: <https://github.com/argoproj/argo-cd/releases>
- Changelog: <https://github.com/argoproj/argo-cd/blob/master/CHANGELOG.md>
- Upgrade guides: <https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/>
- Docs: <https://argo-cd.readthedocs.io/en/stable/>
- Helm chart: <https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd>
- Chart index: <https://argoproj.github.io/argo-helm>
- Leads only: <https://blog.argoproj.io/>

## Skill map

- `SKILL.md` — 217 lines
- `references/01-installation-and-concepts.md` — ArgoCD Installation and Core Concepts
- `references/02-crds-and-configuration.md` — ArgoCD CRDs and Application Configuration
- `references/03-cli-reference-and-best-practices.md` — ArgoCD CLI Reference and Best Practices
- `references/04-security-rbac-sso.md` — ArgoCD Security, RBAC, SSO & Secrets Management Reference
- `references/05-troubleshooting-and-advanced.md` — ArgoCD Troubleshooting and Advanced Patterns
- `scripts/argocd-diagnostics.sh` — (no header comment)
- `scripts/argocd-doc-discover.sh` — (no header comment)
- `scripts/argocd-version-check.sh` — (no header comment)
- `evals/evals.json` — 5 evals

## Watch list

- `references/01-installation-and-concepts.md` — Kubernetes support matrix and `stable` install URL.
- `references/02-crds-and-configuration.md` — Application/ApplicationSet fields flagged beta or new.
- `references/03-cli-reference-and-best-practices.md` — CLI flags (`argocd app sync/diff` options).
- `references/04-security-rbac-sso.md` — RBAC policy syntax, Dex/OIDC config keys.
- `scripts/argocd-version-check.sh` — no baseline constant; add one when the baseline is established.
- Manifest descriptions and the README plugin row — no version stated today.

## Open items

- 2026-09-14: ledger created; establish `verified_version` on the first update run.

## Upgrade log

(no runs yet)

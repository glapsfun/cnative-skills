---
plugin: helm
upstream_name: Helm
version_source: github-release
upstream_repo: helm/helm
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: unknown
verified_proxy: true
verified_date: 2026-06-28
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# helm — upgrade memo

Ledger entry created 2026-09-14. Content cites Helm 3.x only (3.8, 3.13) while upstream latest is the Helm 4 line and `kubernetes-operator` already baselines Helm docs at v4.2.0. First update run must establish whether the skill targets Helm 3, Helm 4, or both. `verified_date` is the plugin's last content commit (proxy) — no verification run yet.

## Sources

- Releases: <https://github.com/helm/helm/releases>
- Docs: <https://helm.sh/docs/>
- CLI reference: <https://helm.sh/docs/helm/>
- Chart template guide: <https://helm.sh/docs/chart_template_guide/>
- Chart best practices: <https://helm.sh/docs/chart_best_practices/>
- Sprig functions: <https://masterminds.github.io/sprig/>
- Artifact Hub: <https://artifacthub.io/>
- Leads only: <https://helm.sh/blog/>

## Skill map

- `SKILL.md` — 119 lines
- `references/01-chart-anatomy-and-authoring.md` — Chart anatomy and authoring
- `references/02-templating-go-and-sprig.md` — Templating: Go text/template + Sprig
- `references/03-cli-and-release-lifecycle.md` — The helm CLI and release lifecycle
- `references/04-debugging-and-validation.md` — Debugging and validation
- `references/05-best-practices.md` — Chart best practices
- `references/06-discovery-and-repos.md` — Discovering and vendoring charts
- `scripts/helm-chart-validate.sh` — helm-chart-validate.sh — read-only quality gate for a Helm chart.
- `scripts/helm-doc-discover.sh` — helm-doc-discover.sh — print authoritative Helm documentation links.
- `scripts/helm-release-debug.sh` — helm-release-debug.sh — collect diagnostics for an installed Helm release.
- `scripts/helm-version-check.sh` — helm-version-check.sh — report the Helm toolchain and target environment.
- `evals/evals.json` — 5 evals

## Watch list

- `references/03-cli-and-release-lifecycle.md` — flags and defaults that differ between Helm 3 and Helm 4.
- `references/01-chart-anatomy-and-authoring.md` — `apiVersion: v2`, dependency handling, `values.schema.json`.
- `scripts/helm-version-check.sh` — reports local toolchain only; has no upstream baseline constant.
- `scripts/helm-doc-discover.sh` — docs repo/ref it lists.
- Cross-plugin: `kubernetes-operator` `references/helm.md` and its Helm baseline.

## Open items

- 2026-09-14: ledger created; establish `verified_version` on the first update run.

## Upgrade log

(no runs yet)

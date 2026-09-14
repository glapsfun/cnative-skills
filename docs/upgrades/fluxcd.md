---
plugin: fluxcd
upstream_name: Flux CD
version_source: github-release
upstream_repo: fluxcd/flux2
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: v2.8.8
verified_date: 2026-06-12
last_upgrade: never
plugin_version: 1.0.1
check_interval_days: 90
---

# fluxcd — upgrade memo

Ledger entry created 2026-09-14. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Releases: <https://github.com/fluxcd/flux2/releases>
- Changelog: <https://github.com/fluxcd/flux2/blob/main/CHANGELOG.md>
- Docs: <https://fluxcd.io/flux/>
- Upgrade guide: <https://fluxcd.io/flux/installation/upgrade/>
- Component API references: <https://fluxcd.io/flux/components/>
- Security: <https://fluxcd.io/flux/security/>
- Leads only: <https://fluxcd.io/blog/>

## Skill map

- `SKILL.md` — 46 lines
- `references/doc-index.md` — Documentation Index
- `references/official-sources.md` — Official Sources
- `references/security-validation.md` — Security and Validation
- `references/troubleshooting.md` — Troubleshooting
- `references/workflows.md` — Workflows
- `scripts/fluxcd-doc-discover.sh` — Lists documentation and CRD/API file paths from official fluxcd GitHub
- `scripts/fluxcd-version-check.sh` — Reports the latest upstream Flux release next to the skill's baseline and

## Watch list

- `references/official-sources.md` — "Baseline collected: 2026-06-12 … v2.8.8".
- `references/security-validation.md` — CVE/go-git note tied to v2.8.8.
- `references/workflows.md` — API versions (`v1`, `v1beta2`) on Kustomization/HelmRelease/OCIRepository.
- `scripts/fluxcd-version-check.sh` — `BASELINE` default (`v2.8.8`).
- Embedded Helm version in helm-controller (moved to Helm 4 in the 2.9 line) affects HelmRelease behaviour notes.

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

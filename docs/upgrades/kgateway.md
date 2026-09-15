---
plugin: kgateway
upstream_name: kgateway
version_source: github-release
upstream_repo: kgateway-dev/kgateway
upstream_url:
upstream_key:
extra_repos: [kubernetes-sigs/gateway-api]
version_match: exact
verified_version: v2.3.3
verified_date: 2026-06-28
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# kgateway — upgrade memo

Ledger entry created 2026-09-14. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Releases: <https://github.com/kgateway-dev/kgateway/releases>
- Docs: <https://kgateway.dev/docs/envoy/latest/>
- Gateway API releases: <https://github.com/kubernetes-sigs/gateway-api/releases>
- CNCF project page: <https://www.cncf.io/projects/kgateway/>

## Skill map

- `SKILL.md` — 438 lines
- `references/gateway-setup.md` — kgateway Gateway Setup Reference
- `references/installation.md` — kgateway Installation & Upgrade Reference
- `references/operations.md` — kgateway Operations Reference
- `references/resiliency.md` — kgateway Resiliency Reference
- `references/security.md` — kgateway Security Reference
- `references/traffic-management.md` — kgateway Traffic Management Reference
- `references/troubleshooting.md` — kgateway Troubleshooting Reference
- `evals/evals.json` — 8 evals

## Watch list

- `SKILL.md` — version matrix table ("v2.3.x latest docs stream", "latest patch observed: v2.3.3", "v2.2.6"), the post-v2.3.1 patch notes list, and `KGATEWAY_VERSION=v2.3.3` snippet.
- `SKILL.md` — Gateway API `v1.5.1` install URLs.
- `references/installation.md` — Helm OCI chart path, version matrix, v2.3.0 migration steps.
- No version-check script; add one when convenient.

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

---
plugin: gcloud
upstream_name: Google Cloud CLI
version_source: web-json
upstream_repo:
upstream_url: https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json
upstream_key: version
extra_repos: []
version_match: exact
verified_version: 576.0.0
verified_date: 2026-07-17
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# gcloud — upgrade memo

Ledger entry created 2026-09-14. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Release notes: <https://docs.cloud.google.com/sdk/docs/release-notes>
- Version manifest (rapid channel): <https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json>
- Docs: <https://docs.cloud.google.com/sdk/docs>
- Command reference: <https://docs.cloud.google.com/sdk/gcloud/reference>
- Install: <https://docs.cloud.google.com/sdk/docs/install-sdk>
- Auth / ADC: <https://docs.cloud.google.com/docs/authentication/application-default-credentials>

## Skill map

- `SKILL.md` — 43 lines
- `references/auth.md` — Authentication
- `references/command-map.md` — Command Map
- `references/config-properties.md` — Configurations and Properties
- `references/doc-index.md` — Documentation Index
- `references/install-components.md` — Install, Components, and Network Setup
- `references/scripting-output.md` — Scripting and Output Control
- `scripts/gcloud-env-report.sh` — Read-only snapshot of the local gcloud environment: named configurations,
- `scripts/gcloud-version-check.sh` — Reports the latest upstream Google Cloud SDK release next to the skill's
- `evals/evals.json` — 5 evals

## Watch list

- `scripts/gcloud-version-check.sh` — `BASELINE_DEFAULT` (`576.0.0`), manifest URL, release-notes URL.
- README plugin row and both manifest descriptions — "verified against Cloud SDK 576.0.0".
- `references/doc-index.md` — doc host (`docs.cloud.google.com`) and page paths.
- `references/install-components.md` — component names and the package-manager lockout note.
- Weekly releases; scan release notes for auth/config/format changes only.

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

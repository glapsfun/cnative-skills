---
plugin: aws
upstream_name: AWS CLI v2
version_source: github-tag
upstream_repo: aws/aws-cli
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: 2.36.1
verified_date: 2026-07-17
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# aws — upgrade memo

Ledger entry created 2026-09-14. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Changelog (authoritative, per patch): <https://github.com/aws/aws-cli/blob/v2/CHANGELOG.rst>
- Tags: <https://github.com/aws/aws-cli/tags>
- User guide: <https://docs.aws.amazon.com/cli/latest/userguide/>
- Install / versioned artifacts: <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html>
- v1 → v2 migration: <https://docs.aws.amazon.com/cli/latest/userguide/cliv2-migration.html>
- Command reference: <https://awscli.amazonaws.com/v2/documentation/api/latest/index.html>

## Skill map

- `SKILL.md` — 43 lines
- `references/auth-credentials.md` — Authentication and Credentials
- `references/command-map.md` — Command Map
- `references/config-profiles.md` — Profiles, Config Files, and Environment Variables
- `references/doc-index.md` — Documentation Index
- `references/install-versioning.md` — Install, Update, Pin, and Migrate
- `references/output-query-scripting.md` — Output, --query, Pagination, and Scripting
- `scripts/aws-env-report.sh` — Read-only report of the local AWS CLI auth/configuration context:
- `scripts/aws-version-check.sh` — Reports the latest upstream AWS CLI v2 release next to the skill's baseline
- `evals/evals.json` — 5 evals

## Watch list

- `scripts/aws-version-check.sh` — `BASELINE_DEFAULT` (`2.36.1`) and the CHANGELOG.rst URL it parses.
- `references/install-versioning.md` — "Content verified against AWS CLI v2 (baseline 2.36.1, July 2026)".
- README plugin row and both manifest descriptions — "verified against AWS CLI 2.36.1".
- `references/auth-credentials.md` — credential precedence chain and SSO session keys.
- Patch releases are near-daily service-model updates; only minor bumps or changelog entries touching CLI behaviour matter.

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

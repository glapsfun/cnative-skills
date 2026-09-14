---
plugin: glab-guru
upstream_name: GitLab CLI
version_source: gitlab-release
upstream_repo: gitlab-org/cli
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: v1.108.0
verified_date: 2026-07-17
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# glab-guru — upgrade memo

Ledger entry created 2026-09-14. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Releases: <https://gitlab.com/gitlab-org/cli/-/releases>
- CLI docs: <https://docs.gitlab.com/cli/>
- CI/CD YAML reference: <https://docs.gitlab.com/ci/yaml/>
- CI/CD components: <https://docs.gitlab.com/ci/components/>
- GitLab release posts (leads): <https://about.gitlab.com/releases/>

## Skill map

- `SKILL.md` — 48 lines
- `references/ci-components.md` — Reusable CI: include, templates, and CI/CD Components
- `references/ci-security.md` — GitLab CI/CD Security
- `references/ci-yaml-authoring.md` — .gitlab-ci.yml Authoring
- `references/doc-index.md` — Upstream Documentation Index
- `references/glab-cli.md` — glab CLI Reference
- `references/pipeline-design.md` — CI/CD Pipeline Design
- `references/troubleshooting.md` — Pipeline Troubleshooting
- `scripts/glab-doc-discover.sh` — Lists documentation file paths from official GitLab projects (gitlab-org/*)
- `scripts/glab-version-check.sh` — Reports the latest upstream glab CLI release next to the skill's baseline,
- `evals/evals.json` — 6 evals

## Watch list

- `scripts/glab-version-check.sh` — `BASELINE_DEFAULT` (`v1.108.0`) and the GitLab permalink API URL.
- README plugin row and both manifest descriptions — "verified against glab v1.108".
- `references/*.md` — CI keywords (`spec:inputs`, `include:integrity`, `workflow:rules`) that GitLab adds monthly.
- glab releases monthly; group several minors into one run.

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

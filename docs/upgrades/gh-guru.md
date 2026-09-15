---
plugin: gh-guru
upstream_name: GitHub CLI
version_source: github-release
upstream_repo: cli/cli
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: v2.96.0
verified_date: 2026-07-17
last_upgrade: never
plugin_version: 1.1.0
check_interval_days: 90
---

# gh-guru — upgrade memo

Ledger entry created 2026-09-14. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Releases: <https://github.com/cli/cli/releases>
- Manual: <https://cli.github.com/manual/>
- GitHub Actions docs: <https://docs.github.com/en/actions>
- GitHub changelog (leads, confirm in docs): <https://github.blog/changelog/>
- go-gh (extensions): <https://github.com/cli/go-gh>

## Skill map

- `SKILL.md` — 48 lines
- `references/cicd-pipeline-design.md` — Designing a CI/CD Process
- `references/custom-actions.md` — Building Custom Actions
- `references/doc-index.md` — Documentation Index
- `references/gh-cli.md` — gh CLI Reference
- `references/repo-management.md` — Repository Management Reference
- `references/security-hardening.md` — Actions Security Hardening
- `references/workflow-authoring.md` — Workflow Authoring Reference
- `scripts/gh-doc-discover.sh` — Lists documentation, template, and example file paths from official GitHub
- `scripts/gh-version-check.sh` — Reports the latest upstream gh CLI release next to the skill's baseline,
- `evals/evals.json` — 6 evals

## Watch list

- `scripts/gh-version-check.sh` — `BASELINE_DEFAULT` (`v2.96.0`).
- README plugin row and both manifest descriptions — "verified against gh v2.96".
- `references/gh-cli.md` — subcommand list and `--json` field names.
- `references/workflow-authoring.md` / `references/custom-actions.md` — pinned action versions (`actions/checkout@v4` etc.) and Node runtime for JS actions.
- `references/security-hardening.md` — Dependabot/OIDC guidance that GitHub changes without a gh release.

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

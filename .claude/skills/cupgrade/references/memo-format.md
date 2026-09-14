# Upgrade memo format

One memo per plugin at `docs/upgrades/<plugin>.md`. The frontmatter is machine-read by
`scripts/cupgrade-status.sh`; the body is read by the next agent (or human) before an
upgrade run. Keep both current — a memo that lies is worse than no memo.

## Frontmatter keys

Flat `key: value` pairs only (no nesting), so the status script can parse them without a
YAML library.

| Key | Required | Meaning |
| --- | --- | --- |
| `plugin` | yes | Plugin directory name under `plugins/` |
| `upstream_name` | yes | Human name of the upstream project ("Argo CD") |
| `version_source` | yes | How to look up the latest upstream version: `github-release`, `github-tag`, `gitlab-release`, `web-json`, or `manual` |
| `upstream_repo` | for github-*/gitlab-* | `owner/repo` (GitLab: full project path) |
| `upstream_url` | for web-json/manual | URL of the JSON manifest, or the page a human checks |
| `upstream_key` | for web-json | Top-level JSON key holding the version string |
| `extra_repos` | no | `[owner/repo, …]` — secondary repos whose releases matter (Helm chart, core vs provider) |
| `version_match` | no | `exact` (default) or `minor` — compare only `MAJOR.MINOR` (docs-baselined projects like Kubernetes) |
| `verified_version` | yes | Upstream version the skill content matches, or `unknown` |
| `verified_date` | yes | ISO date the content was verified (or its last content commit, marked as a proxy in the body) |
| `last_upgrade` | yes | ISO date of the last cupgrade run that changed the plugin, or `never` |
| `plugin_version` | yes | Manifest version at the last upgrade |
| `check_interval_days` | no | Staleness threshold for the status script (default 90) |

## Body sections

```markdown
# <plugin> — upgrade memo

## Sources
Official first. One line per source with its role. These are the only places facts may come from.
- Releases: <url>
- Changelog / upgrade guide: <url>
- Docs: <url>
- Chart / distribution: <url>
- Leads only (blog, announcements): <url>

## Skill map
What lives where, one line per file, so a plan can name its target.
- `SKILL.md` — …
- `references/<file>.md` — …
- `scripts/<file>.sh` — … (upstream endpoint it depends on)
- `evals/evals.json` — <n> evals

## Watch list
Things that go stale and where they are stated: version strings, pinned install snippets,
support matrices, CRD fields flagged beta, endpoints scripts call.

## Open items
Deferred work and cross-plugin fallout, one line each with the run date that raised it.

## Upgrade log
Newest first. One entry per run that changed the plugin (plan-only runs add a one-line note).
```

## Upgrade log entry template

```markdown
### 2026-09-14 — v3.1.0 → v3.5.3 (plugin 1.0.0 → 1.1.0)

Sources consulted:
- <url> — release notes v3.2 … v3.5
- <url> — upgrade guide 3.4→3.5

Applied:
- `references/02-crds-and-configuration.md` — added <feature> section (since v3.4)
- `SKILL.md` — routing line for <feature>; baseline string → v3.5.3
- `scripts/argocd-version-check.sh` — no change needed

Evals: added #6 (<feature> prompt). Smoke: pass — answer named `<field>`.
Checks: scripts/check.sh (shellcheck/markdownlint skipped locally), scripts/test.sh ok.

Reviewed, not applied:
- <release-note item> — internal refactor, no user-facing guidance
```

## Init state

`scripts/cupgrade-memo-init.sh` writes a scaffold with `TODO` markers. Fill them from the
plugin content and the upstream project before the first research step; an init memo with
TODOs left in it is not a baseline.

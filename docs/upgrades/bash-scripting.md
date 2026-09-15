---
plugin: bash-scripting
upstream_name: GNU Bash + shell toolchain
version_source: manual
upstream_repo:
upstream_url: https://git.savannah.gnu.org/cgit/bash.git/tree/NEWS
upstream_key:
extra_repos: [koalaman/shellcheck, mvdan/sh, bats-core/bats-core]
version_match: exact
verified_version: unknown
verified_proxy: true
verified_date: 2026-06-28
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 180
---

# bash-scripting — upgrade memo

Ledger entry created 2026-09-14. Guidance targets Bash 3.2+ portability rather than one release; the interesting drift is in ShellCheck, shfmt, and Bats. Use `cupgrade-releases.sh` on the extra repos. `verified_date` is the plugin's last content commit (proxy) — no verification run yet.

## Sources

- Bash NEWS (per release): <https://git.savannah.gnu.org/cgit/bash.git/tree/NEWS>
- Bash manual: <https://www.gnu.org/software/bash/manual/>
- ShellCheck releases: <https://github.com/koalaman/shellcheck/releases>
- ShellCheck wiki (SC codes): <https://www.shellcheck.net/wiki/>
- shfmt releases: <https://github.com/mvdan/sh/releases>
- Bats releases: <https://github.com/bats-core/bats-core/releases>
- Bats docs: <https://bats-core.readthedocs.io/>
- POSIX shell spec: <https://pubs.opengroup.org/onlinepubs/9799919799/>

## Skill map

- `SKILL.md` — 130 lines
- `references/01-strict-mode-and-structure.md` — Strict mode, script structure, and error handling
- `references/02-defensive-patterns.md` — Defensive patterns
- `references/03-quoting-expansion-arrays.md` — Quoting, expansion, arrays, and tests
- `references/04-debugging-and-testing.md` — Debugging, linting, and testing
- `references/05-portability-posix.md` — Portability: POSIX sh and GNU-vs-BSD (macOS)
- `scripts/bash-doc-discover.sh` — bash-doc-discover.sh — print authoritative shell-scripting documentation links.
- `scripts/bash-lint.sh` — bash-lint.sh — one-command quality gate for shell scripts.
- `scripts/bash-scaffold.sh` — bash-scaffold.sh — print a production-ready bash script skeleton to stdout.
- `scripts/bash-version-check.sh` — bash-version-check.sh — report the shell toolchain and target environment.
- `evals/evals.json` — 5 evals

## Watch list

- `references/01-strict-mode-and-structure.md` — Bash version notes (3.2 macOS vs 4.x/5.x features).
- `references/04-debugging-and-testing.md` — ShellCheck SC codes and Bats syntax.
- `scripts/bash-lint.sh` — shfmt/shellcheck flags; must match the repo's pinned versions in `scripts/bootstrap.sh`.
- `references/05-portability-posix.md` — POSIX edition referenced.

## Open items

- 2026-09-14: ledger created; establish `verified_version` on the first update run.

## Upgrade log

(no runs yet)

# CI/CD Overhaul Design

**Date:** 2026-06-27
**Status:** Approved (design)
**Scope:** Professional CI pipeline, release process, pre-commit framework, and
script-based local validation for the `cnative-skills` repository.

## Context

`cnative-skills` is a **content repository**: Markdown skill docs + JSON manifests
+ Bash utility scripts. There is no compiled application. Plugins are consumed
directly from git, and each `plugin.json` carries its own `version`.

Today the repo has five validators in `.ci/` wired into a single `ci.yml`:
`validate-structure.sh`, `validate-marketplace-sync.sh`, `validate-json.sh`,
`validate-markdown-internal-links.sh`, `validate-shell-syntax.sh`.

This design replaces that with a maintainable, script-canonical CI/CD setup. No
Makefile / `make`: all local developer commands are shell scripts runnable from
the repository root.

## Key decisions

1. **Release model:** repo-level semver tag (`vX.Y.Z`) + GitHub Release. No
   per-plugin release machinery, no binary artifacts, no checksums (nothing is
   downloaded — plugins are consumed from git).
2. **Orchestration:** scripts are canonical. `scripts/*.sh` hold all logic and
   tool invocations. Pre-commit and CI both just invoke the scripts, so local
   validation exactly matches CI with no duplicated tool config.
3. **Missing tools:** `scripts/bootstrap.sh` installs everything. Individual
   scripts **skip with a loud warning** if a tool is absent locally; CI installs
   all tools so nothing is silently skipped in CI.
4. **`.ci/` is deleted**; its logic moves under `scripts/checks/`. CLAUDE.md's
   "Validation" section is updated to point at `scripts/`.

### Scope: deliberately out (YAGNI)

| Requested (generic template) | Decision |
|---|---|
| Source-code compile/lint/test | "Source" here = Markdown/JSON/Bash/YAML; no compile step. |
| TOML validation | **Skipped** — zero TOML files. Clean seam left to add `taplo` later. |
| GoReleaser / binaries / checksums | **Skipped** — repo-level tag + Release, no artifacts. |

### Tools

Net-new: `shellcheck`, `shfmt`, `yamllint`, `actionlint`, `prettier`,
`markdownlint-cli2`, `gitleaks`, `git-cliff` (changelog). Existing: `jq`,
`python3`.

## Architecture

### Script taxonomy (canonical logic)

```
scripts/
  lib/common.sh         # logging, repo_root, have_tool/require_tool, git-tracked file lists
  bootstrap.sh          # install all tools (brew on macOS; apt/go/pip/curl in CI)
  fmt.sh                # shfmt + prettier; default --write, --check for CI
  lint.sh               # shellcheck, yamllint, markdownlint, actionlint
  validate.sh           # runs scripts/checks/* ; supports --fast / --slow
  checks/
    structure.sh          # moved from .ci/validate-structure.sh
    marketplace-sync.sh   # moved from .ci/validate-marketplace-sync.sh
    json.sh               # moved from .ci/validate-json.sh
    yaml.sh               # NEW: yamllint-based parse/lint
    markdown-links.sh     # moved from .ci/validate-markdown-internal-links.sh
    shell-syntax.sh       # moved from .ci/validate-shell-syntax.sh
  test.sh               # evals.json schema check + structure contracts
  security.sh           # gitleaks (--staged for pre-commit, full history in CI)
  check.sh              # ORCHESTRATOR: fast suite by default, --all for everything
  release-dryrun.sh     # changelog preview + version/tag preflight + full check
  install-test.sh       # install smoke test (parse both catalogs, resolve sources)
```

**Script conventions (every script):** `set -euo pipefail`; quoted variables;
runs from repo root via `git rev-parse --show-toplevel`; supports `-h/--help`;
shellcheck-clean; shfmt-formatted; clear error handling; usable locally and in CI.

`scripts/lib/common.sh` provides shared helpers: structured logging, `repo_root`,
`have_tool`/`require_tool` (the skip-with-warning vs hard-require behavior), and
git-tracked file enumeration (all checks operate on `git ls-files` only).

### Fast vs. slow split

| | Speed | Contents | Runs in |
|---|---|---|---|
| **Fast** | seconds | `fmt.sh --check`, `lint.sh`, `validate.sh --fast` (structure, marketplace-sync, json, yaml, shell-syntax) | pre-commit, PR fast job, `check.sh` |
| **Slow** | longer | `validate.sh --slow` (markdown-links), `install-test.sh`, `security.sh` (gitleaks full history) | pre-push (optional), CI slow job, `check.sh --all` |

`scripts/check.sh` = the one command a dev runs before pushing (fast).
`scripts/check.sh --all` = everything CI runs.

## Pre-commit

`.pre-commit-config.yaml` uses **local hooks invoking the scripts** (no duplicated
tool config). Only the fast suite runs on commit:

```yaml
repos:
  - repo: local
    hooks:
      - id: fmt-check
        name: format check (shfmt + prettier)
        entry: scripts/fmt.sh --check
        language: script
        pass_filenames: false
      - id: lint
        name: lint (shellcheck, yamllint, markdownlint, actionlint)
        entry: scripts/lint.sh
        language: script
        pass_filenames: false
      - id: validate
        name: structure + marketplace + json/yaml
        entry: scripts/validate.sh --fast
        language: script
        pass_filenames: false
      - id: gitleaks
        name: secret scan (staged)
        entry: scripts/security.sh --staged
        language: script
        pass_filenames: false
```

`pre-commit install` is documented in README + run by `bootstrap.sh`. Devs without
`pre-commit` lose nothing — CI is the enforcement backstop.

## CI workflow (`.github/workflows/ci.yml`)

Triggers: `pull_request` + `push` to `main`. Least privilege `contents: read`.
Two parallel jobs so slow checks never block fast feedback.

```yaml
name: CI
on:
  pull_request: { branches: [main] }
  push: { branches: [main] }
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  fast:
    name: Fast checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: scripts/bootstrap.sh --ci
      - run: scripts/fmt.sh --check
      - run: scripts/lint.sh
      - run: scripts/validate.sh --fast
  slow:
    name: Slow checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }   # gitleaks full history + link check
      - run: scripts/bootstrap.sh --ci
      - run: scripts/validate.sh --slow
      - run: scripts/install-test.sh
      - run: scripts/security.sh
```

**CI quality gate:** both jobs green = mergeable. The same commands a dev runs
locally, so local matches CI by construction.

## Release process

**Model:** repo-level semver tag `vX.Y.Z` (prereleases `vX.Y.Z-rc.N`). Changelog
via **git-cliff** (single binary, conventional-commit driven). No artifacts/checksums.

### `scripts/release-dryrun.sh` (run locally before tagging)

1. Refuse if working tree is dirty.
2. `scripts/check.sh --all` must pass (release reuses the CI gate).
3. Tag must not already exist; new version must be > latest tag (semver compare).
4. Render `git-cliff --unreleased` and print the changelog that *would* publish.
5. Print prerelease/stable classification derived from the tag string.

### `.github/workflows/release.yml` (triggers on tag push `v*`)

```yaml
permissions:
  contents: write        # only the release job, only to create the Release
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: scripts/bootstrap.sh --ci
      - run: scripts/check.sh --all          # release gate = full suite
      - run: git-cliff --tag "$TAG" > NOTES.md
      - run: |
          gh release create "$TAG" --notes-file NOTES.md \
            $([[ "$TAG" == *-rc.* ]] && echo --prerelease)
```

**Release quality gate:** a tag that fails `check.sh --all` produces **no** Release.

### Recovery / rollback (documented in `docs/RELEASING.md`)

- **Bad release, not yet announced:** `gh release delete vX.Y.Z`,
  `git push --delete origin vX.Y.Z`, fix, re-tag.
- **Already public:** never rewrite — ship `vX.Y.Z+1` as the corrected release;
  mark the bad one "deprecated" in its notes.
- **Workflow failed mid-run:** tag exists but no Release → safe to re-run
  (idempotent; `gh release create` is the only write).

## Implementation roadmap

1. **Foundations** — `scripts/lib/common.sh`, `bootstrap.sh`; move `.ci/*` →
   `scripts/checks/*`; delete `.ci/`; update CLAUDE.md.
2. **Fast checks** — `fmt.sh`, `lint.sh`, `validate.sh`, `check.sh`; add
   `.yamllint`, `.markdownlint-cli2.yaml`, `.prettierignore` configs.
3. **Slow checks** — `markdown-links` check, `install-test.sh`, `security.sh`.
4. **Pre-commit** — `.pre-commit-config.yaml`, README dev-setup section.
5. **CI** — replace `ci.yml` with fast+slow jobs; verify green on a PR.
6. **Release** — `git-cliff.toml`, `release-dryrun.sh`, `release.yml`,
   `docs/RELEASING.md`; dry-run, then cut `v0.1.0`.

Each step ends shellcheck-clean + shfmt-formatted, with `scripts/check.sh` passing.

## Acceptance criteria

- `scripts/check.sh` and `scripts/check.sh --all` exit 0 on a clean tree.
- Every script is `shellcheck`-clean, `shfmt -d` empty, and has `--help`.
- CI fast+slow jobs both green on a PR; identical commands reproduce locally.
- A `v*` tag publishes a GitHub Release with a git-cliff changelog;
  `-rc.N` tags are marked prerelease.
- `.ci/` is removed; CLAUDE.md references updated; no TOML/GoReleaser machinery present.

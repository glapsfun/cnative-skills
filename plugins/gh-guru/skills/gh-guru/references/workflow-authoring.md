# Workflow Authoring Reference

Workflows live in `.github/workflows/*.yml`. Full syntax: <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax>. Validate with `actionlint` when available; runner images, contexts, and syntax evolve, so verify anything version-sensitive against the docs or a test run.

## Skeleton with secure defaults

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm test
```

Every workflow gets: explicit `permissions` (start from `contents: read`), `concurrency` to cancel superseded runs, `timeout-minutes` on jobs, and pinned action versions (SHA for third-party — see `security-hardening.md`).

## Triggers (`on`)

| Trigger | Notes |
| :--- | :--- |
| `push` / `pull_request` | Filter with `branches`, `tags`, `paths` (+ `-ignore` variants). Combined branch+path filters must both match. `pull_request` defaults to types `[opened, synchronize, reopened]` — add `types:` for others (e.g., `labeled`, `ready_for_review`). |
| `workflow_dispatch` | Manual run with typed `inputs` (`choice`, `boolean`, `environment`, `string`, `number`); trigger via UI or `gh workflow run`. |
| `schedule` | POSIX cron, UTC. Runs only on the default branch; may be delayed at busy times; disabled after 60 days of repo inactivity. |
| `workflow_call` | Makes the workflow reusable (see below). |
| `workflow_run` | Fires after another workflow completes — privileged; treat artifacts from the triggering run as untrusted. |
| `pull_request_target` | Runs in the base repo context with secrets on fork PRs — dangerous; see `security-hardening.md` before using. |
| `release`, `issues`, `issue_comment`, `repository_dispatch`, `merge_group` | Event-specific `types` narrow activity. |

Debugging "workflow didn't trigger": confirm the file is on the branch where the event happened (for `push`/`pull_request`, the workflow file must exist on that ref; `schedule`/`workflow_dispatch` read the default branch), check branch/path filters, check `if` conditions by printing contexts (`run: echo '${{ toJSON(github) }}'` — never do this with `secrets`), and remember pushes by `GITHUB_TOKEN` do not trigger new workflow runs (loop prevention — use a PAT or GitHub App token if you genuinely need cascading).

## Expressions and contexts

`${{ }}` expressions can use contexts: `github` (event_name, ref, ref_name, sha, actor, repository, head_ref/base_ref, full `event` payload), `env`, `vars`, `secrets`, `job`, `steps`, `needs`, `strategy`/`matrix`, `runner`, `inputs`. Functions: `contains()`, `startsWith()`, `endsWith()`, `format()`, `join()`, `hashFiles()`, `toJSON()`/`fromJSON()`, and status checks `success()` (default), `failure()`, `cancelled()`, `always()`.

```yaml
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
if: always() && needs.build.result == 'success'    # run even if an earlier optional job failed
```

Context availability varies by key (e.g., `run-name` sees only `github`/`inputs`/`vars`) — check the contexts reference when an expression mysteriously evaluates empty. Never interpolate attacker-controllable context values (issue titles, PR branch names, commit messages) directly into `run:` scripts — route them through `env:` (see `security-hardening.md`).

## Jobs: dependencies, outputs, matrix

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.meta.outputs.version }}
    steps:
      - id: meta
        run: echo "version=1.2.3" >> "$GITHUB_OUTPUT"
  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - run: echo "deploying ${{ needs.build.outputs.version }}"
```

- Step → job outputs via `$GITHUB_OUTPUT`; job → job via `needs.<job>.outputs`. Env vars for later steps: `echo "FOO=bar" >> "$GITHUB_ENV"`; PATH additions via `$GITHUB_PATH`; job summaries via `$GITHUB_STEP_SUMMARY` (Markdown).
- Matrix:

```yaml
strategy:
  fail-fast: false
  matrix:
    os: [ubuntu-latest, macos-latest]
    node: [20, 22]
    include:
      - os: ubuntu-latest
        node: 24
        experimental: true
    exclude:
      - os: macos-latest
        node: 20
runs-on: ${{ matrix.os }}
```

`fail-fast: false` when you want full coverage of failures; `max-parallel` to throttle. Dynamic matrices: generate JSON in a prior job and `matrix: ${{ fromJson(needs.prep.outputs.matrix) }}`.

- `container:` runs steps in a Docker image; `services:` starts sidecars (Postgres, Redis) reachable by hostname = service name (or `localhost:<mapped-port>` on the runner host).

## Caching and artifacts

- **Cache** (speed): setup actions have built-in caching (`actions/setup-node` `cache: npm`, `setup-python` `cache: pip`, `setup-go` on by default). For anything else use `actions/cache` with a `hashFiles`-based key and `restore-keys` fallbacks:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cargo/registry
    key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}
    restore-keys: ${{ runner.os }}-cargo-
```

Caches are scoped by branch (a branch sees its own + default-branch caches), limited per repo (LRU-evicted), and shared with `pull_request_target` — never cache anything derived from untrusted input in privileged workflows.

- **Artifacts** (pass files between jobs / keep results): `actions/upload-artifact` + `actions/download-artifact`, with `retention-days` to control cost. Since v4, artifacts are immutable and named uniquely per job — use `pattern`/`merge-multiple` on download for matrix aggregation.

## Environments and deployments

```yaml
jobs:
  deploy:
    environment:
      name: production
      url: https://example.com
```

Environments carry their own secrets/variables and protection rules: required reviewers (manual approval gates), wait timers, and branch restrictions (only `main` or tags may deploy). Configure via repo Settings → Environments or `gh api`. Use environment secrets for anything deploy-scoped, and OIDC instead of long-lived cloud keys (see `security-hardening.md`).

## Reusable workflows

Callee (`.github/workflows/build.yml`):

```yaml
on:
  workflow_call:
    inputs:
      environment:
        type: string
        required: true
    secrets:
      deploy_key:
        required: true
    outputs:
      image:
        value: ${{ jobs.build.outputs.image }}
```

Caller — `uses` at the **job** level:

```yaml
jobs:
  build:
    uses: my-org/workflows/.github/workflows/build.yml@v1   # or ./.github/workflows/build.yml
    with:
      environment: prod
    secrets: inherit        # or pass explicitly: deploy_key: ${{ secrets.KEY }}
```

Rules of thumb: inputs need explicit `type`; up to 10 levels of nesting (caller + 9); secrets pass only one level unless re-forwarded; environment-level secrets don't traverse `workflow_call` (use repo/org secrets or resolve the environment in the callee); pin cross-repo workflow refs like actions (SHA or tag). Reusable workflows replace whole jobs; composite actions replace step sequences — prefer composite actions when the caller needs to control the job (runner, matrix, surrounding steps).

## Starter workflows and org templates

`actions/starter-workflows` holds GitHub's catalog (ci/, deployments/, automation/, code-scanning/, pages/) — good, current examples for most stacks. Organizations can ship their own: put `workflow-templates/<name>.yml` + `<name>.properties.json` in the org's `.github` repo; `$default-branch` in the template substitutes at use time. These appear in every org repo's "New workflow" page — the cleanest way to standardize CI across an org alongside reusable workflows.

## Debugging runs

```bash
gh run list --workflow ci.yml --limit 10
gh run view <run-id> --log-failed
gh run rerun <run-id> --failed
gh run download <run-id>
```

Re-run with debug logging: `gh run rerun <id> --debug`, or set repo secret/variable `ACTIONS_STEP_DEBUG=true` for step-level debug logs. For flaky infrastructure, check <https://www.githubstatus.com>.

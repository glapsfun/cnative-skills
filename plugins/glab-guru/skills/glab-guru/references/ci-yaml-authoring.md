# .gitlab-ci.yml Authoring

The pipeline configuration language changes with every GitLab minor release: keywords are added (recently `run`, `manual_confirmation`, `workflow:auto_cancel`, `include:integrity`, `spec:inputs:rules`), promoted from beta, or deprecated (`only`/`except` — never generate them). Always validate against the user's instance: `glab ci lint --dry-run --include-jobs` evaluates rules in context, and `glab ci config compile` prints the fully merged YAML with all includes resolved and extends flattened.

## Keyword inventory

- **Global**: `default`, `include`, `stages`, `variables`, `workflow`; header `spec` (in files meant for `include` or components, separated from the body by `---`).
- **Job**: `after_script`, `allow_failure`, `artifacts`, `before_script`, `cache`, `coverage`, `dast_configuration`, `dependencies`, `environment`, `extends`, `hooks`, `identity`, `id_tokens`, `image`, `inherit`, `interruptible`, `manual_confirmation`, `needs`, `pages`, `parallel`, `release`, `resource_group`, `retry`, `rules`, `run`, `script`, `secrets`, `services`, `stage`, `start_in`, `tags`, `timeout`, `trigger`, `variables`, `when`.

A job needs `script` (or `run` or `trigger`); job names starting with `.` are hidden (templates for `extends`). Reserved words cannot be job names (`stages`, `variables`, `include`, `default`, `workflow`, `image`, `services`, `cache`, `true`, `false`, ...).

## Skeleton that avoids the classic traps

```yaml
workflow:
  auto_cancel:
    on_new_commit: interruptible
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

default:
  image: alpine:3.21
  interruptible: true

stages: [build, test, deploy]

build-job:
  stage: build
  script: [make build]
  artifacts:
    paths: [dist/]
    expire_in: 1 week
```

That `workflow:rules` block is the standard duplicate-pipeline guard: without it, pushing to a branch with an open MR creates both a branch pipeline and an MR pipeline.

## rules

Rules evaluate top-down; first match wins; no match means the job is excluded. Key predicates:

```yaml
rules:
  - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    changes:
      paths: [src/**/*, Dockerfile]
      compare_to: refs/heads/main
    when: on_success
  - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
    variables:
      DEPLOY_TIER: production        # rule-level variable override
  - exists:
      paths: ["**/package.json"]
  - when: manual
    allow_failure: true              # manual job that doesn't block the pipeline
```

- `CI_PIPELINE_SOURCE` values: `push`, `merge_request_event`, `schedule`, `web`, `api`, `trigger`, `pipeline` (multi-project), `parent_pipeline`, `chat`, `external`, `external_pull_request_event`, `ondemand_dast_scan`, `webide`, `security_orchestration_policy`.
- In MR pipelines `CI_COMMIT_BRANCH` is not set (use `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME` / `..._TARGET_BRANCH_NAME`); in branch pipelines the `CI_MERGE_REQUEST_*` family is not set.
- Operators: `==`, `!=`, `=~`, `!~`, `&&`, `||`, parentheses; `$VAR` alone tests defined-and-non-empty, `!$VAR` the opposite. Regex literals go between `/.../`; a variable used as a pattern is compared as a string, not a regex.
- `rules:changes` is reliable only in MR pipelines (or with `compare_to`); on new branches or tags it can evaluate true unexpectedly.
- A bare trailing `- when: on_success` makes the job run in *every* pipeline type — the main source of duplicate jobs when `workflow:rules` is absent.
- `when: never` inside `rules` excludes; `manual` gates (pair with `manual_confirmation: "message"` for a confirmation prompt); `delayed` needs `start_in`; `always` on cleanup jobs.

## needs (DAG) and dependencies

```yaml
deploy:
  stage: deploy
  needs:
    - job: build
      artifacts: true
    - job: lint
      optional: true               # tolerate lint being excluded by rules
    - job: build-matrix
      parallel:
        matrix: [{ARCH: amd64}]    # depend on one matrix leg
```

- `needs` breaks stage ordering: the job starts as soon as its needs finish. `needs: []` starts immediately.
- Needing a job that may not exist in the pipeline fails creation ("job ... is not in pipeline / undefined need") unless `optional: true`.
- `dependencies` only restricts artifact download within stage order; `needs` controls both execution order and artifacts. Don't mix them casually.

## artifacts and cache

Artifacts move results between jobs/stages and to the UI; cache speeds up repeated work and is best-effort, per-runner, keyed:

```yaml
test:
  cache:
    key:
      files: [package-lock.json]   # key from lockfile hash
    paths: [node_modules/]
    policy: pull                   # this job only restores; a setup job uses pull-push
    fallback_keys: [default-cache]
  artifacts:
    when: always
    paths: [coverage/]
    reports:
      junit: junit.xml             # test results in MR UI
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura.xml
    expire_in: 30 days
  coverage: '/^Total coverage: (\d+\.\d+)%$/'
```

`artifacts:reports` types include `junit`, `coverage_report`, `dotenv` (pass variables to later jobs), `sast`, `dependency_scanning`, `container_scanning`, `terraform`, and more. Cache paths must be inside the project directory; never cache what you artifact and vice versa without reason.

## variables

Precedence (highest wins): trigger/schedule/pipeline-run variables → project → group → instance → job-level `variables:` in YAML → global `variables:` in YAML → deployment variables → predefined. UI-set variables beat YAML.

```yaml
variables:
  MODE:
    value: fast
    description: "Build mode"       # becomes a dropdown/field in Run pipeline UI
    options: [fast, full]
  RAW_THING:
    value: "$not-expanded"
    expand: false
```

- Everyday predefined variables: `CI_COMMIT_BRANCH`, `CI_COMMIT_TAG`, `CI_COMMIT_SHA`/`CI_COMMIT_SHORT_SHA`, `CI_DEFAULT_BRANCH`, `CI_PIPELINE_SOURCE`, `CI_PROJECT_PATH`/`CI_PROJECT_DIR`, `CI_REGISTRY`/`CI_REGISTRY_IMAGE`, `CI_JOB_TOKEN`, `CI_ENVIRONMENT_NAME`, `CI_MERGE_REQUEST_IID`, `CI_SERVER_FQDN`, `CI_API_V4_URL`. Don't guess beyond these — check the predefined-variables doc.
- `$VAR` in `script` is shell expansion at runtime; in `rules:if`/`include` it's GitLab expansion at pipeline creation. dotenv-created variables don't exist at creation time, so they can't drive `rules`.

## Reuse inside one file: extends, !reference, YAML anchors

```yaml
.go-job:
  image: golang:1.24
  before_script: [go mod download]

unit-test:
  extends: .go-job
  script: [go test ./...]

lint:
  image: golangci/golangci-lint
  script:
    - !reference [.go-job, before_script]   # splice a single section
    - golangci-lint run
```

`extends` merges hashes (job keys win) and replaces arrays wholesale; `!reference` splices specific entries and works across included files, where YAML anchors don't.

## include and spec:inputs

```yaml
include:
  - local: .gitlab/ci/build.yml
  - project: platform/ci-templates
    ref: 8f2a91c4                    # pin cross-project includes to a SHA or tag
    file: /templates/deploy.yml
    inputs:
      environment: staging
  - component: $CI_SERVER_FQDN/platform/components/sast@2.1.0
```

Included files can declare a typed contract in a `spec` header; values are interpolated with `$[[ inputs.name ]]` at compile time (unlike variables — inputs can safely parameterize keys like `stage` or `rules`). See `ci-components.md` for authoring and the catalog, and `ci-security.md` for pinning and `include:integrity`.

## Other keywords worth reaching for

- `services`: sidecar containers (`postgres:16`, `docker:dind`) with `alias`, `variables`, `command`.
- `environment`: `name`, `url`, `on_stop`, `action`, `deployment_tier`, `auto_stop_in` — see `pipeline-design.md`.
- `parallel: 5` or `parallel:matrix` for fan-out (matrix variables combine; each leg is addressable via `needs:parallel:matrix`).
- `retry`: `max: 2` with `when: [runner_system_failure, stuck_or_timeout_failure]` and `exit_codes` — retry infrastructure flakes, not real failures.
- `resource_group`: serializes deploy jobs across pipelines (`process_mode` via API for oldest-first).
- `trigger`: child/multi-project pipelines — see `pipeline-design.md`.
- `release`: create a release from a tag pipeline (uses `release-cli` or newer runner-native support).
- `id_tokens` / `secrets` / `identity`: OIDC and secrets managers — see `ci-security.md`.
- `run`: experimental step-runner syntax (list of `name`/`script`/`step` entries) — don't use it unless the user's instance supports it; `script` remains the default.
- `timeout: 30m` per job; `hooks:pre_get_sources_script` for pre-clone tweaks.

## Validation loop

1. `glab ci lint` — syntax and schema.
2. `glab ci lint --dry-run --ref <branch> --include-jobs` — simulates creation: catches rule mistakes, missing needs, empty pipelines.
3. `glab ci config compile` — inspect the merged YAML when includes/extends/components are involved.
4. `glab ci run -b <branch>` (with user consent) and `glab ci status --live` / `glab ci view` to watch it.

Editors: the Pipeline Editor in the GitLab UI shows lint + merged view + graph; the JSON schema used by editors is `https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json`.

# CI/CD Pipeline Design

How to structure GitLab pipelines as a process — from MR to production — not just as one YAML file. Verify feature availability (merge trains, protected environments, deployment approvals are Premium/Ultimate) against the user's tier and instance version before recommending them.

## Choosing an architecture

| Architecture | Use when | Mechanism |
| :--- | :--- | :--- |
| Basic (stages) | Small projects; simplicity beats speed | `stages` + stage ordering |
| DAG | Bigger graphs; unrelated chains shouldn't wait on each other | `needs` between jobs |
| Parent-child | Monorepo with independent components; keep one repo, split config | `trigger:include`, often with `rules:changes` per component |
| Multi-project | Microservices in separate repos; deployment orchestration repos | `trigger:project` |

```yaml
# Parent-child (monorepo): generate or select per-component child pipelines
frontend:
  rules:
    - changes: {paths: [frontend/**/*]}
  trigger:
    include: frontend/.gitlab-ci.yml
    strategy: depend        # parent mirrors child result; omit to fire-and-forget

# Multi-project
deploy-infra:
  trigger:
    project: platform/infrastructure
    branch: main
    strategy: depend
```

- `strategy: depend` makes the trigger job wait and adopt the downstream status; `strategy: mirror` (newer) also mirrors in real time. Without a strategy the parent succeeds immediately.
- Child pipelines can be **dynamic**: a job generates YAML as an artifact, then `trigger: include: {artifact: child.yml, job: generate}` — the standard answer for "generate jobs programmatically".
- Pass data downstream with `trigger:forward` (pipeline variables / YAML variables) or `needs:pipeline:job` for cross-pipeline artifacts.

## MR pipelines, merged results, merge trains

Three escalating levels for pre-merge confidence:

1. **MR pipelines** (`if: $CI_PIPELINE_SOURCE == "merge_request_event"`): run on the source branch tip; get `CI_MERGE_REQUEST_*` variables.
2. **Merged results pipelines** (project setting): run on an ephemeral merge of source into target — catches "green branch, broken after merge".
3. **Merge trains** (Premium): queue MRs; each train pipeline runs against the preceding train content — protects busy shared branches. Design jobs to be `interruptible` and fast; a slow deploy job in a train stalls everyone (use `rules` to keep deploys out of train pipelines: `if: $CI_MERGE_REQUEST_EVENT_TYPE == "merge_train"`).

Always pair MR pipelines with the `workflow:rules` dedup guard (see `ci-yaml-authoring.md`).

## Environments and promotion

Build once, promote the same artifact — never rebuild per environment. Tag images with `$CI_COMMIT_SHA` (immutable), not `latest`.

```yaml
deploy-staging:
  stage: deploy
  environment:
    name: staging
    url: https://staging.example.com
  resource_group: staging          # one deploy at a time
  script: [./deploy.sh "$CI_COMMIT_SHA" staging]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy-production:
  stage: deploy
  environment:
    name: production
    url: https://example.com
  resource_group: production
  script: [./deploy.sh "$CI_COMMIT_SHA" production]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual                 # or use protected environments + deployment approvals
```

- **Protected environments** (Premium) restrict who can deploy; **deployment approvals** add a required approval step — prefer these over bare `when: manual` for real gates.
- **Review apps**: dynamic environments per MR — `environment: {name: review/$CI_COMMIT_REF_SLUG, on_stop: stop-review, auto_stop_in: 3 days}` plus a stop job with `environment:action: stop` and `when: manual` + `GIT_STRATEGY: none`.
- **Rollback** = redeploy a previous known-good pipeline (environments UI "Rollback" replays the deploy job with its original ref/SHA) — which only works if deploys are self-contained and artifact-pinned. For GitOps-style flows the deploy job updates a manifest repo instead, and rollback is a revert there.
- Incremental rollout options: `.gitlab/ci` timed rollouts with `when: delayed`, canary via two deploy jobs, or hand off to Flux/Argo (see the fluxcd/argocd skills if installed).

## Scheduled and triggered pipelines

- `glab schedule create --cron "0 4 * * *" --ref main --description nightly` — gate schedule-only jobs with `if: $CI_PIPELINE_SOURCE == "schedule"`.
- Trigger tokens (`glab ci run-trig -t $TOKEN`) or `glab api projects/:id/trigger/pipeline` for external systems; `glab ci run --input key:val` passes typed `spec:inputs` values (`int()`, `bool()`, `array()`).

## Efficiency checklist

- `workflow:auto_cancel:on_new_commit: interruptible` + `interruptible: true` on all pre-merge jobs — stop wasting compute on superseded commits.
- `needs` to collapse critical-path time; put slow jobs first in their stage-free DAG.
- Cache keyed on lockfiles with `policy: pull` in consumers; one warm-up job does `pull-push`.
- `rules:changes` to skip whole subtrees in monorepos; `interruptible: false` only on deploys.
- Docker builds: prefer BuildKit/buildah with registry layer cache (`--cache-from $CI_REGISTRY_IMAGE:cache`) over docker-in-docker without caching; kaniko is deprecated upstream.
- Fail fast: cheap lint/typecheck jobs with `needs: []`; `retry` only for infrastructure failure kinds.
- Watch pipeline duration in CI/CD analytics; a pipeline over ~10 min pre-merge changes developer behavior.

## Runners

Jobs run where their `tags` match registered runners (instance, group, or project scope). `glab runner list` shows the fleet. Common failure: a job with a tag no runner advertises sits pending forever — see `troubleshooting.md`. On gitlab.com, hosted runners include Linux (default, `saas-linux-*` sizes), macOS, Windows, and GPU-enabled tags.

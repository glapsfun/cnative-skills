# Designing a CI/CD Process

This is the process-level view: how to assemble the mechanics from `workflow-authoring.md`, `security-hardening.md`, and `repo-management.md` into a coherent path from pull request to production. Use it when the user asks for "CI/CD for this project", a delivery process, or a promotion/deployment strategy — not just a single workflow file.

## Discover before designing

A pipeline encodes team decisions, so establish them first (ask, or infer from the repo and say what you assumed):

- **What is shipped?** Library (publish to a registry), service (deploy a container), static site (Pages/CDN), CLI (release binaries). This decides the delivery half of the pipeline.
- **When does production change?** On every merge to main (continuous deployment), on a tag/release (release-driven), or on a schedule/manual approval (release trains). Default recommendation: continuous deployment to staging, tag- or approval-gated production.
- **What environments exist** and what may reach each one? Map each to a GitHub environment with its own secrets and protection rules.
- **What must never break?** Those checks become required status checks in the ruleset; everything else is advisory.

## Stage architecture

Order stages so cheap, high-signal feedback comes first and expensive/privileged operations come last:

```
PR:            lint + format → unit tests → build → integration tests → security scans
merge to main: (same CI) → build+push image/artifact (SHA-tagged) → deploy staging → smoke/E2E
tag v*:        promote tested artifact → deploy production (approval-gated) → verify → release notes
```

Principles:

- **Fail fast, in parallel.** Lint, unit tests, and build are independent jobs, not sequential steps; `needs` only where a real data dependency exists (deploy needs the image digest).
- **Build once, promote the artifact.** The image/binary tested in staging is byte-for-byte what reaches production — promote by digest/SHA tag, never rebuild per environment. Rebuilding invalidates everything the earlier stages proved.
- **Same checks everywhere.** The PR pipeline and the main pipeline run the same CI jobs (one reusable workflow called from both), so "green on PR" predicts "green on main".
- **Scans in the PR, not after.** `dependency-review-action`, CodeQL/SAST, and secret scanning block problems before merge; post-merge scanning is monitoring, not gating.
- **Keep PR feedback under ~10 minutes.** Push slower suites (full E2E, performance, exhaustive matrix) to merge-time, nightly (`schedule`), or a `merge_group` queue instead of every PR push.

Concrete skeleton (three files, one reusable core):

```
.github/workflows/
  ci.yml        # on: workflow_call — lint, test, build jobs (the shared core)
  pr.yml        # on: pull_request — calls ci.yml
  main.yml      # on: push (main) — calls ci.yml, then build+push image, deploy staging, E2E
  release.yml   # on: push tags v* — deploy production (environment: production), gh release create
```

## Environment promotion

Model each environment as a GitHub environment and let protection rules — not tribal knowledge — define the gates:

| Environment | Trigger | Protection |
| :--- | :--- | :--- |
| preview (optional) | PR open/update | none; ephemeral, torn down on close |
| staging | merge to main | branch restricted to `main`; no approval |
| production | tag `v*` or manual promote | required reviewers, branch/tag restriction, optionally a wait timer |

- Deployment jobs set `environment: <name>` so environment secrets, OIDC subject claims (`environment:production` in the trust policy), approvals, and deployment history all attach to the right place.
- Promotion = running the deploy job against the next environment with the **same artifact reference** (image digest passed as a workflow input/output), via tag push, `workflow_dispatch` with an `environment` input, or an approval on the queued production job.
- If the project uses GitOps (Argo CD/Flux), the pipeline's "deploy" step becomes "bump the image tag in the environment's manifest repo/path via PR" — the GitOps controller does the rollout; CI still owns build, test, and image publishing.

## Deployment strategy

Pick based on blast radius and rollback needs; encode it in the deploy step, not in more YAML ceremony:

- **Rolling** (default for k8s/ASG targets): gradual replacement, health-check gated. Cheap, brief version coexistence.
- **Blue/green**: full parallel stack, switch traffic atomically; instant rollback by switching back. Costs double capacity during deploys.
- **Canary**: shift a small percentage, watch error/latency metrics, then promote or abort. Best safety for high-traffic services; needs real metrics and (ideally) automated analysis.
- **Feature flags / dark launch**: deploy inert code continuously, release by toggling flags. Decouples deploy from release; pairs well with trunk-based development and continuous deployment.

Rollback is part of the design, not an afterthought: keep the last known-good artifact reference recorded (release assets, deployment API, or the GitOps history), make "redeploy previous digest" a one-command/manual-dispatch path, and test it. A post-deploy verification job (smoke test + a short metrics check) should either fail loudly or trigger the rollback path automatically.

## Versioning and release cadence

- Services on continuous deployment: version by commit SHA + moving `latest`-per-environment tags; cut semver tags only for humans (changelogs, rollback points).
- Libraries/CLIs/actions: semver tags drive everything (`release.yml` on `v*`), `gh release create --generate-notes` with `.github/release.yml` grouping, artifacts + checksums + provenance attestations attached.
- Protect the release path: tag ruleset on `v*` (no moving/deleting), releases cut only from the default branch, the release workflow is the only thing with `contents: write`/`packages: write`.

## Cross-cutting requirements

Apply regardless of the shape chosen:

- **Security defaults** from `security-hardening.md` in every workflow: least-privilege `permissions`, SHA-pinned actions, OIDC for cloud access, no untrusted interpolation, Dependabot for `github-actions`.
- **Concurrency**: cancel superseded PR runs (`cancel-in-progress: true`); for deploy jobs use a per-environment group **without** cancel (never kill a half-finished deploy — queue instead).
- **Merge gating**: the ruleset's required status checks reference the exact job names of the PR pipeline; adding a new mandatory check means updating both.
- **Observability of the pipeline itself**: job summaries (`$GITHUB_STEP_SUMMARY`) for build/deploy results, failure notifications to chat only for main/production pipelines (PR failures are visible in the PR), and periodic review of Actions usage/duration to catch slow drift.
- **Reproducibility**: `npm ci`-style lockfile installs, pinned tool versions via setup actions, no `latest` base images in release builds.

## Anti-patterns to steer away from

- Rebuilding the artifact per environment ("works in staging" proves nothing about prod).
- One giant workflow where deploy steps hide behind `if:` chains — split by trigger; reuse via `workflow_call`.
- Deploying from PR-triggered workflows or granting deploy credentials to PR runs (fork danger; see `security-hardening.md`).
- Approval gates on everything — approvals belong on production (and secrets-bearing environments), not on lint.
- Long-lived environment branches (`develop`/`release/*`) when trunk + tags + environments would do; extra branches multiply drift and merge ceremony.
- Skipping staging "just this once" via manual dispatch straight to prod — if a break-glass path exists, make it explicit, logged, and approval-gated.

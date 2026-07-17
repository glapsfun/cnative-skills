# GitLab CI/CD Security

Defaults every generated pipeline should follow, and what to look for when reviewing one. Applies to gitlab.com and self-managed; feature tiers noted where relevant.

## Secrets: prefer short-lived OIDC over stored variables

Stored CI/CD variables are the weakest option (long-lived, visible to anyone who can run a job that echoes them). Escalation path:

**First choice: OIDC `id_tokens`** — per-job JWTs GitLab signs; cloud providers and Vault trust them, no stored secret at all:

```yaml
deploy:
  id_tokens:
    AWS_TOKEN:
      aud: https://gitlab.example.com
  script:
    - aws sts assume-role-with-web-identity --web-identity-token "$AWS_TOKEN" ...
```

Claims available for trust policies: `project_path`, `ref`, `ref_type`, `ref_protected`, `environment`, `environment_protected`, `deployment_tier`, `namespace_path`, `pipeline_source`, and more. Bind cloud roles to `project_path` **and** `ref_protected: true` (or a specific `environment`), never to the bare issuer.

**Second choice: external secrets managers** via the `secrets` keyword (Vault, GCP Secret Manager, Azure Key Vault, AWS Secrets Manager) or the native GitLab Secrets Manager (beta):

```yaml
job:
  id_tokens:
    VAULT_ID_TOKEN: {aud: https://vault.example.com}
  secrets:
    DB_PASSWORD:
      vault: production/db/password@kv   # path@engine
      file: false                        # default true = path-to-file variable
```

**Last resort: stored variables**, when unavoidable: `--masked` (hidden in logs; value must be maskable), `--hidden` (masked + never revealable in UI again), `--protected` (only on protected branches/tags — always for deploy credentials), `--raw` (no `$` expansion), environment-scoped (`--scope prod`). `glab variable set KEY --masked --protected --scope prod`. File-type variables for kubeconfigs/keys.

Never `echo` secrets, pass them as CLI args (visible in `ps`/logs), or write them into artifacts. `artifacts:paths` catching a `.env` is a classic leak.

## CI_JOB_TOKEN

The job token is powerful and its blast radius is project-configurable:

- Keep the **job token allowlist** (Settings → CI/CD → Job token permissions) restricted to the specific projects that need inbound access; the "all projects can access" legacy mode is being removed.
- Fine-grained permissions for the job token let you scope what it can do, not just where.
- It authenticates `docker login $CI_REGISTRY -u gitlab-ci-token -p $CI_JOB_TOKEN`, package registry pulls, and a limited API subset — for anything more, mint a project access token with minimal scope/role and short expiry (`glab token create --access-level developer --scope read_api --duration 7d`), don't use a personal token of a human.

## Protect the refs that deploy

- **Protected branches/tags**: deploy credentials marked `protected` are only injected on protected refs — this is the core control that stops a random feature branch from deploying to prod. Configure via UI or `glab api projects/:id/protected_branches -f name='release/*' ...`.
- **Protected environments + deployment approvals** (Premium): restrict who can deploy `production` and require approvals; stronger than `when: manual`.
- **Pipeline execution policies / compliance frameworks** (Ultimate): enforce security jobs across projects so individual `.gitlab-ci.yml` files can't remove them.

## Fork and MR risks

MR pipelines from forks run the *fork's* `.gitlab-ci.yml` — treat that YAML as attacker-controlled:

- Protected variables are not exposed to fork pipelines by default; keep it that way. Be wary of the "Allow fork pipelines to run in parent project" setting — combined with secrets it recreates GitHub's `pull_request_target` foot-gun.
- Pipeline variables in `rules:if` comparisons and MR titles/descriptions interpolated into `script` are injection surfaces: quote everything, route untrusted text through variables, don't build shell from MR metadata.
- Review-app deploys for external contributors should require a maintainer's manual play.

## Supply chain

- Pin what you include and run: `include:project` with `ref:` (SHA or tag), components pinned to SHA or exact semver (never `~latest` in production), `include:remote` only with `integrity: sha256-...`, container images by digest (`image@sha256:...`) for release pipelines.
- Read a component's source before first use — catalog listing is not review.
- GitLab scanners as components/templates: SAST, Secret Detection, Dependency Scanning, Container Scanning, DAST, IaC scanning, License scanning. Minimum for any project: SAST + Secret Detection (free tier) — `include: [template: Jobs/SAST.gitlab-ci.yml, template: Jobs/Secret-Detection.gitlab-ci.yml]` or their component equivalents.
- Provenance/attestation: SLSA provenance from runners (`RUNNER_GENERATE_ARTIFACTS_METADATA`), verify with `glab attestation verify`; sign images with cosign using `id_tokens` (SIGSTORE_ID_TOKEN) keyless flow.

## Review checklist for an existing pipeline

1. `only`/`except` present? Migrate to `rules` (deprecated syntax, subtly different semantics).
2. Duplicate-pipeline guard (`workflow:rules`) present?
3. Any secret in plain `variables:` in YAML? Move to protected/masked variables or OIDC.
4. Deploy jobs: protected refs? `resource_group`? `environment` declared (so it shows in deployment history and can be rolled back)? Not `interruptible`?
5. Includes/components/images pinned to immutable refs?
6. `CI_JOB_TOKEN` allowlist reviewed? Personal tokens replaced with project/group tokens?
7. Untrusted input (MR titles, branch names with `CI_COMMIT_REF_NAME`, commit messages) interpolated into scripts unquoted?
8. `artifacts` capturing secret files? `expire_in` set so old artifacts age out?

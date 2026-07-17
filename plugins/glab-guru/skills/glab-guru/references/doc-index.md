# Upstream Documentation Index

Where current GitLab CI and glab docs live. Run `bash scripts/glab-doc-discover.sh` for a live listing of doc file paths; the rendered docs are at `https://docs.gitlab.com/<path>` (strip `doc/` and `_index.md`/`.md` from repo paths).

## GitLab CI docs (gitlab-org/gitlab, `doc/ci/`)

| Area | Path | Rendered |
| :--- | :--- | :--- |
| CI landing + quick start | `doc/ci/_index.md`, `doc/ci/quick_start/` | docs.gitlab.com/ci/ |
| **YAML keyword reference** | `doc/ci/yaml/_index.md` | docs.gitlab.com/ci/yaml/ |
| YAML details | `doc/ci/yaml/{includes,needs,workflow,script,expressions,yaml_optimization,artifacts_reports,deprecated_keywords}.md` | docs.gitlab.com/ci/yaml/... |
| Jobs, rules, job token | `doc/ci/jobs/{job_rules,job_control,ci_job_token,fine_grained_permissions,job_artifacts}.md` | docs.gitlab.com/ci/jobs/... |
| Pipeline types & architecture | `doc/ci/pipelines/{pipeline_architectures,pipeline_types,merge_request_pipelines,merged_results_pipelines,merge_trains,downstream_pipelines,pipeline_efficiency,schedules,settings}.md` | docs.gitlab.com/ci/pipelines/... |
| Variables | `doc/ci/variables/{_index,predefined_variables,where_variables_can_be_used}.md` | docs.gitlab.com/ci/variables/... |
| Components & catalog | `doc/ci/components/_index.md`, `doc/ci/inputs/` | docs.gitlab.com/ci/components/ |
| Secrets & OIDC | `doc/ci/secrets/{_index,id_token_authentication,hashicorp_vault,gcp_secret_manager,azure_key_vault,aws_secrets_manager}.md` | docs.gitlab.com/ci/secrets/... |
| Pipeline security / SLSA | `doc/ci/pipeline_security/` | docs.gitlab.com/ci/pipeline_security/ |
| Environments & deploys | `doc/ci/environments/{_index,deployments,protected_environments,deployment_approvals,deployment_safety,incremental_rollouts}.md`, `doc/ci/review_apps/` | docs.gitlab.com/ci/environments/... |
| Runners | `doc/ci/runners/{_index,configure_runners,runners_scope,hosted_runners/}.md` | docs.gitlab.com/ci/runners/... |
| Docker builds | `doc/ci/docker/{using_docker_build,docker_in_docker,using_buildkit,docker_layer_caching,buildah_rootless_tutorial}.md` | docs.gitlab.com/ci/docker/... |
| Caching | `doc/ci/caching/_index.md` | docs.gitlab.com/ci/caching/ |
| Services (db sidecars) | `doc/ci/services/` | docs.gitlab.com/ci/services/ |
| Testing/reports/coverage | `doc/ci/testing/` | docs.gitlab.com/ci/testing/ |
| **Debugging** | `doc/ci/debugging.md` | docs.gitlab.com/ci/debugging/ |
| Migration (Jenkins, GH Actions, CircleCI, ...) | `doc/ci/migration/` | docs.gitlab.com/ci/migration/ |
| Triggers, chatops, resource groups, secure files | `doc/ci/{triggers,chatops,resource_groups,secure_files}/` | — |

Also: pipeline JSON schema `app/assets/javascripts/editor/schema/ci.json` (same repo), CI/CD Catalog `gitlab.com/explore/catalog`, API reference `docs.gitlab.com/api/` (pipelines, jobs, variables, protected branches).

## glab CLI docs (gitlab-org/cli, `docs/source/`)

Rendered at `docs.gitlab.com/cli/`. One directory per command group (`mr/`, `issue/`, `ci/`, `job/`, `release/`, `repo/`, `variable/`, `schedule/`, `token/`, `api/`, `auth/`, `cluster/`, `stack/`, `duo/`, `mcp/`, `skills/`, ...), one file per subcommand — mirrors `glab <group> <subcommand> --help`. Agent Skills for glab: `docs.gitlab.com/cli/skills/`. Releases and changelog: `gitlab.com/gitlab-org/cli/-/releases`.

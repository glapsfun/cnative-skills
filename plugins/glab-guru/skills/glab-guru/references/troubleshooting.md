# Pipeline Troubleshooting

Debug in trigger-to-job order: was a pipeline created → is the job in it → is the job running → why did the step fail. Jumping straight to the failing script wastes time when the real problem is a rule or a runner tag.

## 1. No pipeline was created

`glab ci list --per-page 5` / `glab ci list --source merge_request_event` — is anything there for your ref?

- **`workflow:rules` filtered it out** — the most common cause. Simulate: `glab ci lint --dry-run --ref <branch> --include-jobs`. A dry run that yields zero jobs means every job's rules said no ("Pipeline will not run for the selected trigger. The rules configuration prevented any jobs from being added to the pipeline.").
- **Expecting an MR pipeline but nothing configured for it**: MR pipelines only exist if at least one job has `if: $CI_PIPELINE_SOURCE == "merge_request_event"` (or `workflow:rules` allows it).
- **Syntax error** = "yaml invalid" badge on the commit: `glab ci lint` locally; check `glab ci list --yaml-errors`. Frequent offenders: tabs, unquoted `:` in scripts, `!reference` typos, a job with no `script`/`run`/`trigger`, reserved word as job name.
- **Push options / skip**: commit message containing `[ci skip]` or push with `-o ci.skip`.
- **Permissions/quota**: user without permission on protected branch, no compute minutes left, or the pipeline was created but immediately failed with no jobs — check the pipeline's failure reason via `glab api projects/:fullpath/pipelines/<id>`.

## 2. Pipeline exists, job missing

- `rules` first-match-wins: an early rule with `when: never`, or no rule matching at all (no match = excluded). Compare `glab ci lint --dry-run --include-jobs` output between refs.
- `rules:changes` semantics: in branch pipelines on a *new* branch it evaluates against the push before; on tags and schedules it's always true unless `compare_to` is set. Use `compare_to: refs/heads/main` for deterministic behavior.
- Job name starts with `.` (hidden), or the stage isn't listed in `stages`.
- In MR pipelines, rules using `$CI_COMMIT_BRANCH` never match (that variable is unset there) — use `$CI_MERGE_REQUEST_*` variables.
- "job: xyz is not in pipeline / undefined need": a `needs` target was excluded by its own rules — add `optional: true` or align the rules.

## 3. Job stuck pending / stuck created

- **Pending**: no live runner matches the job's `tags` (or job is untagged but runners require tags — "This job is stuck because you don't have any active runners"). `glab runner list`, check runner is online, not paused, tag spelling, and whether it accepts untagged jobs. Protected-branch jobs need runners allowed on protected refs.
- **Created (manual dependencies)**: waiting on `needs` targets, a `resource_group` slot, or an earlier manual job without `allow_failure: true`.
- **Scheduled**: `when: delayed` + `start_in`.

## 4. Job runs and fails

```bash
glab ci status --live                 # overview
glab ci view                          # interactive: jobs, logs, retry from terminal
glab ci trace <job-name>              # stream one job's log
glab job artifact <ref> <job> -p out/ # pull artifacts to inspect locally
glab ci retry                         # after a fix (mutation: confirm with user)
```

- Script exit code is the job result; `set -e` semantics apply per line of `script`. Multi-line scripts: prefer `|` block scalars; watch YAML eating quotes and `$`.
- **Variable empty in job**: protected variable on an unprotected ref; environment-scoped variable with non-matching `environment`; masked variable that failed masking requirements (then it's simply not masked or set); precedence override from group/instance level.
- **Cache "misses"** are normal across runners (cache is per-runner unless distributed cache is configured); artifacts are the guaranteed transport.
- **Artifacts**: "could not retrieve the needed artifacts" → the producing job's artifacts expired (`expire_in`), were excluded, or `dependencies`/`needs` don't include the producer. Size limit exceeded → check max artifact size (instance/project setting).
- **Docker jobs**: `docker: command not found` → wrong image or missing dind service; dind needs `services: [docker:dind]` + `DOCKER_HOST=tcp://docker:2376` + privileged runner (or use buildah/BuildKit rootless).
- **Auth in jobs**: `CI_JOB_TOKEN` denied cross-project → target project's job token allowlist (Settings → CI/CD → Job token permissions) must list the calling project.
- **Timeouts**: job `timeout`, runner-level timeout (the lower wins), and `after_script` having its own limit.

## 5. MR pipeline confusion

- Two pipelines per push (branch + MR) → add the standard `workflow:rules` guard.
- "Pipeline must succeed" blocks merge but no pipeline runs → project requires pipelines, but config produces none for MRs; either add MR-pipeline jobs or disable the requirement.
- Merged results / merge train pipeline fails while branch pipeline passed → the failure comes from the ephemeral merge with the target; reproduce with `refs/merge-requests/<iid>/merge`.
- Fork MRs: no protected variables, may need maintainer approval to run — expected, don't "fix" by exposing secrets.

## Instance-level checks

`glab api version` (instance version — confirms whether a YAML keyword can exist there), `glab api projects/:fullpath` (visibility of CI settings), Settings → CI/CD for: job token allowlist, protected variables, runner assignment, default timeout, auto-cancel settings. GitLab status page (`status.gitlab.com`) when gitlab.com itself misbehaves.

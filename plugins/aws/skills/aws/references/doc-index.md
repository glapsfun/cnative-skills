# Documentation Index

Official sources only. Doc trees are versioned in the URL: `cli/latest/` is the **v2** user guide and command reference; `cli/v1/` is the v1 (maintenance-mode) guide. Always match the tree to the user's installed major version — pin links to `cli/v1/` only when the user is stuck on v1.

## User guide (v2)

- What is the AWS CLI: <https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html>
- Install/update latest: <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html>
- Install past (pinned) releases: <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html>
- Docker images: <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-docker.html>
- Configure overview + precedence: <https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html>
- Config/credentials file settings: <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html>
- Environment variables: <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html>
- Authentication chapter: <https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html>
- IAM Identity Center (SSO): <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html>
- Assume role: <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html>
- External credential process: <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sourcing-external.html>
- Output formats: <https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-output-format.html>
- Filtering (--query / JMESPath): <https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-filter.html>
- Pagination + pager: <https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-pagination.html>
- Return codes: <https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-returncodes.html>
- Skeletons and input files: <https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-skeleton.html>
- Retries: <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-retries.html>
- Endpoints: <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-endpoints.html>
- High-level S3 commands: <https://docs.aws.amazon.com/cli/latest/userguide/cli-services-s3-commands.html>
- v1→v2 migration/breaking changes: <https://docs.aws.amazon.com/cli/latest/userguide/cliv2-migration-changes.html>
- Troubleshooting: <https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-troubleshooting.html>

## Command reference (v2)

- Index: <https://docs.aws.amazon.com/cli/latest/reference/>
- Per command: `https://docs.aws.amazon.com/cli/latest/reference/<service>/<command>.html`

Live equivalents on any installed CLI: `aws help`, `aws <service> help`, `aws <service> <command> help`.

## v1 (maintenance mode)

- v1 user guide: <https://docs.aws.amazon.com/cli/v1/userguide/cli-chap-welcome.html>
- End-of-support announcement: <https://aws.amazon.com/blogs/developer/cli-v1-maintenance-mode-announcement/>
- Maintenance policy / version matrix: <https://docs.aws.amazon.com/sdkref/latest/guide/maint-policy.html>

## Releases (used by scripts/aws-version-check.sh)

- v2 changelog (first heading = latest release): <https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst>
- Source repo: <https://github.com/aws/aws-cli> (v2 development on the `v2` branch)
- JMESPath language: <https://jmespath.org/> (tutorial + spec for `--query`)

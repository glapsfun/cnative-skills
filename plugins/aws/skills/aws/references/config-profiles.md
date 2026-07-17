# Profiles, Config Files, and Environment Variables

## The two files

| File | Default path | Holds | Section headers |
|---|---|---|---|
| config | `~/.aws/config` (`AWS_CONFIG_FILE`) | Everything non-secret: region, output, SSO, roles, settings | `[default]`, `[profile name]`, `[sso-session name]`, `[services name]` |
| credentials | `~/.aws/credentials` (`AWS_SHARED_CREDENTIALS_FILE`) | Access keys only | `[default]`, `[name]` — **no `profile` prefix** |

The `[profile x]` (config) vs `[x]` (credentials) asymmetry is the single most common hand-editing mistake — a profile that "doesn't exist" usually has the wrong header form in one file. Credentials-file settings win over config-file settings for the same profile. Keep secrets out of `config`; everything else belongs there.

## Working with profiles

```bash
aws configure                      # wizard for [default]
aws configure --profile work       # wizard for a named profile
aws configure set region eu-west-1 --profile work
aws configure get region --profile work
aws configure list                 # effective values + where each came from
aws configure list-profiles        # all profile names (v2)
aws s3 ls --profile work           # per-command
export AWS_PROFILE=work            # per-shell
```

Typical multi-account layout — SSO session shared, one profile per account/role:

```ini
[profile dev]
sso_session = my-sso
sso_account_id = 111122223333
sso_role_name = DevAccess
region = eu-central-1

[profile prod]
sso_session = my-sso
sso_account_id = 999988887777
sso_role_name = ReadOnly
region = eu-central-1

[sso-session my-sso]
sso_region = us-east-1
sso_start_url = https://my-org.awsapps.com/start
sso_registration_scopes = sso:account:access
```

Advise per-shell `AWS_PROFILE` (or direnv per project directory) over relying on `default`, and `aws sts get-caller-identity` before anything destructive.

## Setting precedence

Command-line flag > environment variable > profile setting > built-in default. Region specifically: `--region` > `AWS_REGION` > `AWS_DEFAULT_REGION` > profile `region`. `AWS_REGION` is the SDK-compatible variable added in v2 and beats `AWS_DEFAULT_REGION` — mixed exports of both are a classic "commands go to the wrong region" cause.

## Environment variables that matter

Credentials and identity:

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` — override all profile credentials.
- `AWS_PROFILE` — profile to use; overridden by `--profile`.
- `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_ROLE_SESSION_NAME` — assume role with web identity (OIDC CI).
- `AWS_EC2_METADATA_DISABLED`, `AWS_METADATA_SERVICE_TIMEOUT`, `AWS_METADATA_SERVICE_NUM_ATTEMPTS` — IMDS behavior.

Behavior:

- `AWS_REGION` / `AWS_DEFAULT_REGION` — see precedence above.
- `AWS_DEFAULT_OUTPUT` — output format (profile key: `output`).
- `AWS_PAGER` — pager program; empty string disables (profile key: `cli_pager`).
- `AWS_CLI_AUTO_PROMPT` — `on` / `on-partial` interactive prompting (profile key: `cli_auto_prompt`).
- `AWS_MAX_ATTEMPTS`, `AWS_RETRY_MODE` (`legacy`|`standard`|`adaptive`) — retry handler (profile keys: `max_attempts`, `retry_mode`; use `standard` or `adaptive` in scripts).
- `AWS_ENDPOINT_URL`, `AWS_ENDPOINT_URL_<SERVICE>` — endpoint overrides (LocalStack, MinIO, FIPS setups); `AWS_IGNORE_CONFIGURED_ENDPOINT_URLS=true` ignores all of them.
- `AWS_CA_BUNDLE` — custom CA for HTTPS (profile key: `ca_bundle`); corporate-proxy TLS interception fix. Proxies themselves use standard `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`.
- `AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE` — relocate the files (cannot be set in a profile).
- `AWS_CLI_FILE_ENCODING` — text-file encoding for `file://` params (v2's embedded Python ignores `PYTHONUTF8`).

## Notable config-file-only settings

- `cli_binary_format` — `base64` (v2 default) or `raw-in-base64-out` (v1-style blob handling).
- `cli_timestamp_format` — `iso8601` (default) or `wire`.
- `cli_pager` — pager command; empty disables.
- `credential_process` — external credential helper.
- `parameter_validation`, `tcp_keepalive`, `api_versions` (v1 only — removed in v2).
- `[services X]` sections — per-service endpoint overrides referenced from a profile via `services = X`.
- S3-specific block under a profile (`s3 = ...` subsection): `max_concurrent_requests` (default 10), `max_queue_size`, `multipart_threshold`, `multipart_chunksize`, `max_bandwidth`, `use_accelerate_endpoint`, `addressing_style` — tune for big `s3 cp`/`sync` jobs.

Full settings list: <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html>; env vars: <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html>

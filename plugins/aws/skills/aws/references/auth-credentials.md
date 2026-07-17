# Authentication and Credentials

The credential system is the AWS CLI's most misdiagnosed area. Two rules before touching anything:

1. **Find out what identity is actually in effect**: `aws sts get-caller-identity` (whoami) and `aws configure list` (which source each value came from: env, profile, IMDS…).
2. **Know the precedence chain** — a stray `AWS_ACCESS_KEY_ID` in the environment silently beats the default profile and even a profile selected via `AWS_PROFILE`; only an explicit `--profile` flag on the command line overrides environment credentials.

## Credential precedence (highest wins)

1. Command line options (`--profile`, `--region`, `--output`)
2. Environment variables (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN`)
3. Assume role (`role_arn` in config, or web identity)
4. IAM Identity Center (SSO) profile settings in `~/.aws/config`
5. `~/.aws/credentials` file
6. External `credential_process`
7. `~/.aws/config` file credentials
8. ECS/container credentials (task role)
9. EC2 instance profile (IMDS)

Classic bugs this explains: exported test keys overriding the profile selected with `AWS_PROFILE` (an explicit `--profile` flag is the one selector that beats env credentials); a container getting the task role instead of the mounted credentials file it was expected to use; "I changed the credentials file but nothing happened" (env vars still set).

## Recommended: IAM Identity Center (SSO) for humans

Short-lived, auto-refreshing credentials from your org's identity source. Setup:

```bash
aws configure sso        # wizard: session name, start URL (or issuer URL, 2.22.0+), SSO region, scopes
aws sso login --profile my-dev-profile
aws sts get-caller-identity --profile my-dev-profile   # verify
aws sso logout           # drop cached tokens
```

Resulting modern ("SSO token provider") config — the `sso-session` section is shared across profiles and supports automatic token refresh:

```ini
[profile my-dev-profile]
sso_session = my-sso
sso_account_id = 111122223333
sso_role_name = PowerUserAccess
region = eu-central-1
output = json

[sso-session my-sso]
sso_region = us-east-1
sso_start_url = https://my-org.awsapps.com/start
sso_registration_scopes = sso:account:access
```

- **Legacy SSO config** (all `sso_*` keys directly in the profile, no `sso-session` section) still works but cannot auto-refresh tokens — migrate to the sso-session form when users complain about frequent re-logins.
- 2.22.0+ uses browser PKCE authorization by default; `--use-device-code` restores device-code flow for headless/remote boxes.
- Tokens cache under `~/.aws/sso/cache/`. "The SSO session associated with this profile has expired" → `aws sso login` again (nothing is wrong with the profile).

## Assume role via config

Chain any base credential to a role — no secrets for the role itself:

```ini
[profile base]
# credentials in ~/.aws/credentials under [base], or an SSO profile

[profile prod-admin]
role_arn = arn:aws:iam::999988887777:role/Admin
source_profile = base          # or: credential_source = Ec2InstanceMetadata | Environment | EcsContainer
role_session_name = vlad-cli   # shows up in CloudTrail
# mfa_serial = arn:aws:iam::111122223333:mfa/vlad   # prompts for MFA code
# external_id = ...            # for third-party cross-account roles
# duration_seconds = 3600
```

`aws --profile prod-admin s3 ls` transparently calls STS AssumeRole and caches the temporary credentials. One-off equivalent: `aws sts assume-role --role-arn ... --role-session-name ...` (returns AccessKeyId/SecretAccessKey/SessionToken you must export yourself — prefer the profile form).

## CI and workloads: no long-term keys

- **CI with OIDC (GitHub Actions, GitLab, etc.)**: assume role with web identity. Config keys `role_arn` + `web_identity_token_file` (env: `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_ROLE_SESSION_NAME`); most CI platforms have a wrapper (e.g. `aws-actions/configure-aws-credentials`). No stored secret at all.
- **EC2**: attach an instance profile; credentials arrive via IMDS automatically (tune `AWS_METADATA_SERVICE_TIMEOUT`/`AWS_METADATA_SERVICE_NUM_ATTEMPTS` if flaky; `AWS_EC2_METADATA_DISABLED=true` to opt out).
- **ECS/EKS**: task roles / pod identity provide container credentials automatically.
- **Anything else**: `credential_process = /path/to/helper` in a profile runs an external program that prints a JSON credential document — the bridge for vaults and SSO brokers. Only as secure as the helper; treat it as last resort alongside long-term keys.

## Long-term access keys (last resort)

`aws configure` writes `aws_access_key_id`/`aws_secret_access_key` to `~/.aws/credentials`. If a user must use them: scope the IAM policy tightly, rotate regularly, never commit the file, and prefer adding `aws_session_token` short-term keys or an MFA-gated assume-role on top. `aws configure import --csv file://creds.csv` imports console-generated CSVs.

## Triage table

| Symptom | Likely cause → fix |
|---|---|
| `Unable to locate credentials` | Nothing in the chain: no env vars, no profile, no role. `aws configure list` to confirm, then set up SSO or a profile; check `AWS_PROFILE` spelling. |
| `ExpiredToken` / `ExpiredTokenException` | Temporary credentials aged out. SSO: `aws sso login`. Assume-role env exports: re-assume. Stale `AWS_SESSION_TOKEN` in env: unset all three `AWS_*` key vars. |
| `The SSO session associated with this profile has expired` | `aws sso login --profile <p>` (or `--sso-session <s>`). |
| `An error occurred (AccessDenied) … AssumeRole` | Base identity lacks `sts:AssumeRole` on the role, or the role's trust policy doesn't trust it; check `mfa_serial`/`external_id` requirements. |
| Works interactively, fails in cron/CI | Interactive shell had env vars or an SSO browser session. Give the job its own mechanism (role, OIDC, credential_process) and set `AWS_PROFILE` explicitly. |
| `InvalidClientTokenId` / `SignatureDoesNotMatch` | Wrong/rotated/partial keys (or clock skew — check system time). Re-enter credentials; look for a shadowing env var. |
| Right credentials, wrong account | Multiple profiles; `default` isn't what they think. `aws sts get-caller-identity` and pass `--profile` explicitly. |

Full method-by-method docs: <https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html>

#!/usr/bin/env bash
set -euo pipefail

# Read-only report of the local AWS CLI auth/configuration context:
# installed version, profiles, effective settings, credential-related
# environment variables (set/unset only — values of secrets are never
# printed), and config file presence. Makes no network calls; the only
# commands run are local `aws configure ...` inspections, and
# `aws configure list` masks key material by itself.

usage() {
  cat <<EOF
Usage: aws-env-report.sh [-h|--help]

Print a read-only summary of the local AWS CLI configuration: version,
profiles, effective settings source, AWS_* environment variables (secret
values redacted), and config file presence. No network calls.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    echo "unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

if ! command -v aws >/dev/null 2>&1; then
  echo "aws: not found (install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
  exit 0
fi

echo "Version:"
version_line="$(aws --version 2>&1 || true)"
echo "  ${version_line%%$'\n'*}"

echo
echo "Profiles (aws configure list-profiles):"
if profiles="$(aws configure list-profiles 2>/dev/null)"; then
  if [ -n "${profiles}" ]; then
    printf '%s\n' "${profiles}" | sed 's/^/  /'
  else
    echo "  (none configured)"
  fi
else
  echo "  (unavailable — AWS CLI v1 has no list-profiles)"
fi

echo
echo "Effective settings for the active profile (aws configure list; secrets masked by the CLI):"
aws configure list 2>&1 | sed 's/^/  /' || true

echo
echo "Credential/config environment variables:"
secret_vars=(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN)
plain_vars=(AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION AWS_DEFAULT_OUTPUT AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE AWS_ENDPOINT_URL AWS_CA_BUNDLE AWS_PAGER)
any_env_set=0
for var in "${secret_vars[@]}"; do
  if [ -n "${!var:-}" ]; then
    echo "  ${var}=<set, redacted>"
    any_env_set=1
  fi
done
for var in "${plain_vars[@]}"; do
  if [ -n "${!var:-}" ]; then
    echo "  ${var}=${!var}"
    any_env_set=1
  fi
done
if [ "${any_env_set}" -eq 0 ]; then
  echo "  (none of the checked AWS_* variables are set)"
fi

echo
echo "Files:"
config_file="${AWS_CONFIG_FILE:-${HOME}/.aws/config}"
credentials_file="${AWS_SHARED_CREDENTIALS_FILE:-${HOME}/.aws/credentials}"
for f in "${config_file}" "${credentials_file}"; do
  if [ -f "${f}" ]; then
    echo "  ${f}: present"
  else
    echo "  ${f}: absent"
  fi
done
if [ -d "${HOME}/.aws/sso/cache" ] && [ -n "$(ls -A "${HOME}/.aws/sso/cache" 2>/dev/null)" ]; then
  echo "  ${HOME}/.aws/sso/cache: SSO token cache present"
fi

echo
echo "To confirm the live identity/account (one STS network call), run: aws sts get-caller-identity"

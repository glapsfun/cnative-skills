#!/usr/bin/env bash
set -euo pipefail

# Reports the latest upstream AWS CLI v2 release next to the skill's baseline
# and the locally installed aws version.
#
# Security posture:
# - Read-only: one HTTPS GET to raw.githubusercontent.com (the official
#   aws/aws-cli v2 changelog, first bytes only via a Range request) plus
#   read-only local checks (`aws --version`); nothing fetched is executed.
# - The version taken from the changelog is validated against a strict
#   character allowlist before printing, so changelog content cannot inject
#   free-form text into the agent's context.
#
# Failure behavior: if curl is missing or the fetch fails (offline, blocked),
# the upstream fields degrade to "unknown" with a warning on stderr and the
# local report still prints.

BASELINE_DEFAULT="2.36.1"
CHANGELOG_URL="https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst"

usage() {
  cat <<EOF
Usage: aws-version-check.sh [-h|--help]

Report the installed aws version and the latest upstream AWS CLI v2 release
versus the skill baseline. Read-only.

Environment:
  AWS_GURU_BASELINE   Skill baseline version (default: ${BASELINE_DEFAULT})
EOF
}

if [ "$#" -gt 1 ]; then
  echo "unexpected extra arguments" >&2
  usage >&2
  exit 2
fi

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

BASELINE="${AWS_GURU_BASELINE:-${BASELINE_DEFAULT}}"
CURL_ARGS=(-fsSL --proto '=https' --connect-timeout 5 --max-time 15 -H 'Range: bytes=0-4095')

latest_version=""
if ! command -v curl >/dev/null 2>&1; then
  echo "warning: curl not found; skipping the upstream release check" >&2
elif ! changelog_head="$(curl "${CURL_ARGS[@]}" "${CHANGELOG_URL}")"; then
  echo "warning: could not fetch ${CHANGELOG_URL} (network error or blocked); reporting local information only" >&2
else
  # First "N.N.N" heading line in the RST changelog is the latest release.
  latest_version="$(printf '%s\n' "${changelog_head}" \
    | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"
fi

# Sanitize the changelog-derived value: dotted version digits only.
if ! [[ ${latest_version} =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
  latest_version=""
fi

echo "AWS CLI v2 upstream latest: ${latest_version:-unknown}"
echo "Changelog: ${CHANGELOG_URL}"
echo "Skill baseline snapshot: ${BASELINE}"

if [ -n "${latest_version}" ] && [ "${latest_version}" != "${BASELINE}" ]; then
  echo "Notice: upstream latest differs from the skill baseline; check the changelog before version-specific advice."
fi

echo
if command -v aws >/dev/null 2>&1; then
  echo "Local aws:"
  version_line="$(aws --version 2>&1 | head -n1 || true)"
  echo "  ${version_line}"
  case "${version_line}" in
    aws-cli/1.*)
      echo "  note: this is AWS CLI v1 (maintenance mode, end-of-support announced) — recommend migrating to v2"
      ;;
    aws-cli/2.*)
      local_version="${version_line#aws-cli/}"
      local_version="${local_version%% *}"
      if [ -n "${latest_version}" ] && [ "${local_version}" != "${latest_version}" ]; then
        echo "  note: local ${local_version} is behind upstream ${latest_version}"
      fi
      ;;
  esac
  echo
  echo "For auth/configuration state, run: bash scripts/aws-env-report.sh"
else
  echo "Local aws: not found (install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
fi

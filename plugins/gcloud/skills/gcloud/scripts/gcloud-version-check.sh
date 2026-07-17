#!/usr/bin/env bash
set -euo pipefail

# Reports the latest upstream Google Cloud SDK release next to the skill's
# baseline and the locally installed gcloud version.
#
# Security posture:
# - Read-only: one HTTPS GET to dl.google.com (the official Cloud SDK release
#   manifest) plus read-only local checks (`gcloud --version`); nothing
#   fetched is executed.
# - The version taken from the manifest is validated against a strict
#   character allowlist before printing, so manifest content cannot inject
#   free-form text into the agent's context.
#
# Failure behavior: if curl or python3 is missing, or the fetch fails
# (offline, blocked), the upstream fields degrade to "unknown" with a warning
# on stderr and the local report still prints.

BASELINE_DEFAULT="576.0.0"
MANIFEST_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json"
RELEASE_NOTES_URL="https://docs.cloud.google.com/sdk/docs/release-notes"

usage() {
  cat <<EOF
Usage: gcloud-version-check.sh [-h|--help]

Report the installed gcloud version and the latest upstream Google Cloud SDK
release versus the skill baseline. Read-only.

Environment:
  GCLOUD_GURU_BASELINE   Skill baseline version (default: ${BASELINE_DEFAULT})
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

BASELINE="${GCLOUD_GURU_BASELINE:-${BASELINE_DEFAULT}}"
CURL_ARGS=(-fsSL --proto '=https' --connect-timeout 5 --max-time 15)

latest_version=""
if ! command -v curl >/dev/null 2>&1; then
  echo "warning: curl not found; skipping the upstream release check" >&2
elif ! command -v python3 >/dev/null 2>&1; then
  echo "warning: python3 not found; skipping the upstream release check" >&2
elif ! manifest_json="$(curl "${CURL_ARGS[@]}" "${MANIFEST_URL}")"; then
  echo "warning: could not fetch ${MANIFEST_URL} (network error or blocked); reporting local information only" >&2
else
  latest_version="$(printf '%s' "${manifest_json}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version", ""))' 2>/dev/null)" \
    || latest_version=""
fi

# Sanitize the manifest-derived value: dotted version digits only.
if ! [[ ${latest_version} =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
  latest_version=""
fi

echo "Cloud SDK upstream latest: ${latest_version:-unknown}"
echo "Release notes: ${RELEASE_NOTES_URL}"
echo "Skill baseline snapshot: ${BASELINE}"

if [ -n "${latest_version}" ] && [ "${latest_version}" != "${BASELINE}" ]; then
  echo "Notice: upstream latest differs from the skill baseline; check release notes before version-specific advice."
fi

echo
if command -v gcloud >/dev/null 2>&1; then
  echo "Local gcloud:"
  gcloud --version 2>/dev/null | sed 's/^/  /' || true
  sdk_root="$(gcloud info --format='value(installation.sdk_root)' 2>/dev/null || true)"
  if [ -n "${sdk_root}" ]; then
    echo "  sdk_root: ${sdk_root}"
    case "${sdk_root}" in
      /usr/lib/google-cloud-sdk | /usr/lib64/google-cloud-sdk)
        echo "  note: package-manager install; 'gcloud components' is disabled — use apt/dnf packages instead"
        ;;
    esac
  fi
  if [ -n "${latest_version}" ]; then
    local_version="$(gcloud --version 2>/dev/null | sed -n 's/^Google Cloud SDK \([0-9.]*\).*/\1/p')"
    if [ -n "${local_version}" ] && [ "${local_version}" != "${latest_version}" ]; then
      echo "  note: local ${local_version} is behind upstream ${latest_version}"
    fi
  fi
  echo
  echo "For auth/configuration state, run: bash scripts/gcloud-env-report.sh"
else
  echo "Local gcloud: not found (install: https://docs.cloud.google.com/sdk/docs/install-sdk)"
fi

#!/usr/bin/env bash
set -euo pipefail

# Reports the latest upstream Flux release next to the skill's baseline and
# any locally available Flux CLI / cluster deployment versions.
#
# Security posture:
# - Read-only: one HTTPS GET to api.github.com plus read-only local checks
#   (`flux --version`, `kubectl get deploy`); nothing fetched is executed.
# - Every value taken from the API response (tag, date, URL) is validated
#   against a strict pattern before printing, so release metadata cannot
#   inject free-form text into the agent's context.

REPO="${FLUXCD_REPO:-fluxcd/flux2}"
BASELINE="${FLUXCD_BASELINE_VERSION:-v2.8.8}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to check the latest Flux release" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse the release metadata" >&2
  exit 1
fi

latest_json="$(curl -fsSL --proto '=https' --max-time 30 "${API_URL}")"

json_field() {
  printf '%s' "${latest_json}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1" 2>/dev/null \
    || true
}

latest_tag="$(json_field tag_name)"
published_at="$(json_field published_at)"
release_url="$(json_field html_url)"

# Reject anything that does not look like the expected value shape.
if ! [[ ${latest_tag} =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]{1,32})?$ ]]; then
  latest_tag=""
fi
if ! [[ ${published_at} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  published_at=""
fi
if ! [[ ${release_url} =~ ^https://github\.com/${REPO}/releases/tag/[0-9A-Za-z._-]{1,64}$ ]]; then
  release_url=""
fi

echo "Flux upstream latest: ${latest_tag:-unknown}"
echo "Published: ${published_at:-unknown}"
echo "Release notes: ${release_url:-${API_URL}}"
echo "Skill baseline snapshot: ${BASELINE}"

if [ -n "${latest_tag}" ] && [ "${latest_tag}" != "${BASELINE}" ]; then
  echo "Notice: upstream latest differs from the skill baseline; inspect release notes before version-specific advice."
fi

if command -v flux >/dev/null 2>&1; then
  echo
  echo "Local Flux CLI:"
  flux --version || true
else
  echo
  echo "Local Flux CLI: not found"
fi

if command -v kubectl >/dev/null 2>&1 && [ -n "${KUBECONFIG:-}" ]; then
  echo
  echo "Cluster Flux deployments:"
  kubectl -n flux-system get deploy -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image --no-headers 2>/dev/null || true
fi

#!/usr/bin/env bash
set -euo pipefail

REPO="${FLUXCD_REPO:-fluxcd/flux2}"
BASELINE="${FLUXCD_BASELINE_VERSION:-v2.8.8}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to check the latest Flux release" >&2
  exit 1
fi

latest_json="$(curl -fsSL "${API_URL}")"

latest_tag="$(printf '%s' "${latest_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null || true)"
published_at="$(printf '%s' "${latest_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("published_at",""))' 2>/dev/null || true)"
release_url="$(printf '%s' "${latest_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("html_url",""))' 2>/dev/null || true)"

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

#!/usr/bin/env bash
set -euo pipefail

# Reports the latest upstream Karpenter AWS provider release next to the
# skill's baseline and any locally visible Karpenter installation (self-hosted
# controller or EKS Auto Mode markers).
#
# Security posture:
# - Read-only: one HTTPS GET to api.github.com plus read-only local checks
#   (`kubectl get`); nothing fetched is executed.
# - Every value taken from the API response (tag, date, URL) is validated
#   against a strict character allowlist before printing, so release metadata
#   cannot inject free-form text into the agent's context.
#
# Failure behavior: if curl or python3 is missing, or the API call fails
# (offline, rate limit), the upstream fields degrade to "unknown" with a
# warning on stderr and the local report still prints.

REPO="${KARPENTER_REPO:-aws/karpenter-provider-aws}"
BASELINE="${KARPENTER_BASELINE_VERSION:-v1.13.0}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
CURL_ARGS=(-fsSL --proto '=https' --max-time 30)

latest_json=""
if ! command -v curl >/dev/null 2>&1; then
  echo "warning: curl not found; skipping the upstream release check" >&2
elif ! command -v python3 >/dev/null 2>&1; then
  echo "warning: python3 not found; skipping the upstream release check" >&2
elif ! latest_json="$(curl "${CURL_ARGS[@]}" "${API_URL}")"; then
  echo "warning: could not fetch ${API_URL} (network error or API rate limit); reporting local information only" >&2
  latest_json=""
fi

json_field() {
  printf '%s' "${latest_json}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1" 2>/dev/null \
    || true
}

latest_tag=""
published_at=""
release_url=""
if [ -n "${latest_json}" ]; then
  latest_tag="$(json_field tag_name)"
  published_at="$(json_field published_at)"
  release_url="$(json_field html_url)"
fi

# Sanitize API-derived values: allowlisted characters only, no free-form text.
if ! [[ ${latest_tag} =~ ^[0-9A-Za-z._-]{1,64}$ ]]; then
  latest_tag=""
fi
if ! [[ ${published_at} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  published_at=""
fi
# Literal prefix comparison (no regex interpolation of ${REPO}); the remaining
# tag segment must match the same allowlist as latest_tag.
release_prefix="https://github.com/${REPO}/releases/tag/"
release_tag_part="${release_url#"${release_prefix}"}"
if [ "${release_tag_part}" = "${release_url}" ] \
  || ! [[ ${release_tag_part} =~ ^[0-9A-Za-z._-]{1,64}$ ]]; then
  release_url=""
fi

echo "Karpenter upstream latest (${REPO}): ${latest_tag:-unknown}"
echo "Published: ${published_at:-unknown}"
echo "Release notes: ${release_url:-${API_URL}}"
echo "Skill baseline snapshot: ${BASELINE}"

if [ -n "${latest_tag}" ] && [ "${latest_tag}" != "${BASELINE}" ]; then
  echo "Notice: upstream latest differs from the skill baseline; inspect release notes before version-specific advice."
fi

# Probe for a reachable cluster (works with implicit ~/.kube/config, not just
# an exported KUBECONFIG); short timeout so an unreachable API server can't hang.
if command -v kubectl >/dev/null 2>&1 \
  && kubectl version --request-timeout=2s >/dev/null 2>&1; then
  echo
  echo "Cluster Karpenter (self-hosted controller, if any):"
  kubectl get deploy -A -l app.kubernetes.io/name=karpenter --request-timeout=5s \
    -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image --no-headers 2>/dev/null \
    || true
  echo
  echo "NodeClass CRDs present (karpenter.k8s.aws = self-hosted, eks.amazonaws.com = Auto Mode):"
  kubectl get crd -o name --request-timeout=5s 2>/dev/null | grep -E 'ec2nodeclasses\.karpenter\.k8s\.aws|nodeclasses\.eks\.amazonaws\.com|nodepools\.karpenter\.sh' || echo "none found"
fi

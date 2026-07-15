#!/usr/bin/env bash
set -euo pipefail

# Reports the latest upstream agentgateway release next to the skill's
# baseline, plus any locally available agentgateway CLI / Kubernetes
# deployment version and config-schema-migration status. agentgateway's
# config schema is actively evolving (binds/llm.port/mcp.port deprecated in
# favor of gateways/llm.gateways/mcp.gateways), so checking drift here is
# more important than for a stable, slow-moving tool.
#
# Security posture:
# - Read-only: one HTTPS GET to api.github.com plus read-only local checks
#   (`agentgateway --version`, `helm list`, `kubectl get`); nothing fetched
#   is executed.
# - Every value taken from the API response (tag, date, URL) is validated
#   against a strict character allowlist before printing, so release
#   metadata cannot inject free-form text into the agent's context.
#
# Failure behavior: if curl or python3 is missing, or the API call fails
# (offline, rate limit), the upstream fields degrade to "unknown" with a
# warning on stderr and the local CLI/cluster report still prints.

REPO="${AGENTGATEWAY_REPO:-agentgateway/agentgateway}"
BASELINE="${AGENTGATEWAY_BASELINE_VERSION:-v1.3.1}"
NAMESPACE="${AGENTGATEWAY_NAMESPACE:-agentgateway-system}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
CURL_ARGS=(-fsSL --proto '=https' --max-time 30)

usage() {
  cat <<'EOF'
Usage: agentgateway-version-check.sh

Read-only agentgateway version/context helper. Checks the latest upstream
release against a baked-in baseline, the local agentgateway CLI version, and
(if reachable) the agentgateway/agentgateway-crds Helm releases and
GatewayClass on the current Kubernetes context.

Environment:
  AGENTGATEWAY_REPO=agentgateway/agentgateway   GitHub repo to check for latest release
  AGENTGATEWAY_BASELINE_VERSION=v1.3.1          Version this skill's content was verified against
  AGENTGATEWAY_NAMESPACE=agentgateway-system    Namespace containing the agentgateway control plane
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

section() {
  printf '\n## %s\n' "$1"
}

section "Upstream release"
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
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" 2>/dev/null \
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

echo "agentgateway upstream latest: ${latest_tag:-unknown}"
echo "Published: ${published_at:-unknown}"
echo "Release notes: ${release_url:-${API_URL}}"
echo "Skill baseline snapshot: ${BASELINE}"

if [ -n "${latest_tag}" ] && [ "${latest_tag}" != "${BASELINE}" ]; then
  echo "Notice: upstream latest differs from the skill baseline; inspect release notes for config-schema changes (agentgateway's binds/gateways migration is still in progress) before giving version-specific advice."
fi

section "Config schema migration reminder"
echo "agentgateway's config schema is mid-migration; grep the user's config file"
echo "(or 'agctl proxy config' output) for these deprecated top-level keys:"
echo "  binds:     -> superseded by gateways: (map) + top-level routes/tcpRoutes"
echo "  llm.port:  -> superseded by llm.gateways"
echo "  mcp.port:  -> superseded by mcp.gateways"
echo "See references/config-model.md for the full old-vs-new comparison."

section "Local CLI"
if command -v agentgateway >/dev/null 2>&1; then
  version_json="$(agentgateway --version 2>/dev/null || true)"
  if [ -n "${version_json}" ]; then
    echo "${version_json}"
  else
    echo "agentgateway CLI: found but --version produced no output"
  fi
else
  echo "agentgateway CLI: not found"
fi

echo
if command -v agctl >/dev/null 2>&1; then
  echo "agctl: found"
else
  echo "agctl: not found"
fi

section "Kubernetes"
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl: not found"
elif ! kubectl version --request-timeout=2s >/dev/null 2>&1; then
  echo "kubectl: found, but no reachable cluster API server"
else
  echo "kubectl context: $(kubectl config current-context 2>/dev/null || echo unknown)"

  if command -v helm >/dev/null 2>&1; then
    echo
    echo "Helm releases in namespace '${NAMESPACE}':"
    helm_releases="$(helm list -n "${NAMESPACE}" --filter '^agentgateway(-crds)?$' 2>/dev/null || true)"
    if [ -n "${helm_releases}" ]; then
      echo "${helm_releases}"
    else
      echo "No agentgateway/agentgateway-crds Helm releases found or namespace is inaccessible"
    fi
  fi

  echo
  echo "agentgateway control-plane images in namespace '${NAMESPACE}':"
  deploy_images="$(kubectl -n "${NAMESPACE}" get deploy --request-timeout=5s \
    -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image \
    --no-headers 2>/dev/null || true)"
  if [ -n "${deploy_images}" ]; then
    echo "${deploy_images}"
  else
    echo "No deployments found or namespace is inaccessible"
  fi

  echo
  echo "agentgateway GatewayClass:"
  kubectl get gatewayclass agentgateway --request-timeout=5s \
    -o custom-columns=NAME:.metadata.name,CONTROLLER:.spec.controllerName \
    --no-headers 2>/dev/null || echo "GatewayClass 'agentgateway' not found or cluster is inaccessible"
fi

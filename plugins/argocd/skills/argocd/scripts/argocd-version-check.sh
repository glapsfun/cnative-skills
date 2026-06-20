#!/usr/bin/env bash
set -euo pipefail

REPO="${ARGOCD_REPO:-argoproj/argo-cd}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
SKIP_NETWORK="${ARGOCD_SKIP_NETWORK:-false}"

usage() {
  cat <<'EOF'
Usage: argocd-version-check.sh

Read-only Argo CD version/context helper.

Environment:
  ARGOCD_REPO=argoproj/argo-cd       GitHub repo to check for latest release
  ARGOCD_NAMESPACE=argocd            Namespace containing Argo CD control plane
  ARGOCD_SKIP_NETWORK=true           Skip GitHub release lookup
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
if [[ "${SKIP_NETWORK}" == "true" ]]; then
  echo "Skipped GitHub release lookup because ARGOCD_SKIP_NETWORK=true"
elif ! command -v curl >/dev/null 2>&1; then
  echo "curl not found; cannot check latest upstream release"
elif ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found; cannot parse GitHub release response"
else
  latest_json="$(curl -fsSL "${API_URL}" 2>/dev/null || true)"
  if [[ -z "${latest_json}" ]]; then
    echo "Unable to fetch latest release from ${API_URL}"
  else
    latest_tag="$(printf '%s' "${latest_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null || true)"
    published_at="$(printf '%s' "${latest_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("published_at",""))' 2>/dev/null || true)"
    release_url="$(printf '%s' "${latest_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("html_url",""))' 2>/dev/null || true)"
    echo "Argo CD upstream latest: ${latest_tag:-unknown}"
    echo "Published: ${published_at:-unknown}"
    echo "Release notes: ${release_url:-${API_URL}}"
  fi
fi

section "Local CLI"
if command -v argocd >/dev/null 2>&1; then
  argocd version --client 2>/dev/null || argocd version 2>/dev/null || true
else
  echo "argocd CLI: not found"
fi

section "Kubernetes context"
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl: not found"
elif ! kubectl config current-context >/dev/null 2>&1; then
  echo "kubectl context: unavailable"
elif ! kubectl version --request-timeout=5s >/dev/null 2>&1; then
  echo "kubectl context: $(kubectl config current-context)"
  echo "kubectl API: unreachable"
else
  echo "kubectl context: $(kubectl config current-context)"

  echo
  echo "Argo CD control-plane images in namespace '${NAMESPACE}':"
  kubectl -n "${NAMESPACE}" get deploy,statefulset \
    -o custom-columns=KIND:.kind,NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image \
    --no-headers 2>/dev/null || echo "No Argo CD deployments/statefulsets found or namespace is inaccessible"

  echo
  echo "Argo CD CRDs:"
  kubectl get crd \
    applications.argoproj.io \
    appprojects.argoproj.io \
    applicationsets.argoproj.io \
    -o custom-columns=NAME:.metadata.name,VERSION:.spec.versions[0].name \
    --no-headers 2>/dev/null || echo "Argo CD CRDs not found or cluster is inaccessible"
fi

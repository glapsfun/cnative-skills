#!/usr/bin/env bash
set -euo pipefail

section() {
  printf '\n## %s\n' "$1"
}

KUBECTL_REQUEST_TIMEOUT="${KUBECTL_REQUEST_TIMEOUT:-10s}"

run_or_note() {
  local description="$1"
  shift
  printf '%s\n' "$description"
  if ! "$@" 2>&1; then
    printf 'not available or command failed\n'
  fi
}

section "Local tools"
if command -v kubectl >/dev/null 2>&1; then
  kubectl version --client=true --output=yaml 2>/dev/null || kubectl version --client=true
else
  echo "kubectl: not found"
fi

if command -v helm >/dev/null 2>&1; then
  helm version --short 2>/dev/null || helm version
else
  echo "helm: not found"
fi

if command -v flux >/dev/null 2>&1; then
  flux --version
else
  echo "flux: not found"
fi

if command -v argocd >/dev/null 2>&1; then
  argocd version --client --short 2>/dev/null || argocd version --client
else
  echo "argocd: not found"
fi

if ! command -v kubectl >/dev/null 2>&1; then
  exit 0
fi

section "Kubernetes context"
run_or_note "Current context:" kubectl config current-context
run_or_note "Cluster info:" kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" cluster-info

section "Kubernetes server"
run_or_note "Server version:" kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" version --output=yaml

section "API discovery"
run_or_note "Core API resources:" kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" api-resources

section "Schema probes"
for target in \
  "deploy.spec.strategy" \
  "pod.spec.containers.readinessProbe" \
  "networkpolicy.spec.ingress" \
  "persistentvolumeclaim.spec" \
  "role.rules"; do
  printf '\n### kubectl explain %s\n' "$target"
  kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" explain "$target" --recursive 2>&1 || echo "explain not available for ${target}"
done

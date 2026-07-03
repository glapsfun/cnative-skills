#!/usr/bin/env bash
set -euo pipefail

SKIP_CLUSTER="${SRE_SKIP_CLUSTER:-false}"

usage() {
  cat <<'EOF'
Usage: sre-env-discovery.sh

Read-only environment discovery for SRE investigations. Reports available
CLI tooling, Kubernetes context, GitOps managers, and cloud providers.
Never mutates anything and never prints secret values.

Environment:
  SRE_SKIP_CLUSTER=true   Skip all live-cluster calls (offline mode)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

section() {
  printf '\n## %s\n' "$1"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

section "Tooling"
for tool in kubectl helm kustomize flux argocd git gh glab aws gcloud az terraform pulumi jq curl; do
  if have "$tool"; then
    printf 'present  %s\n' "$tool"
  else
    printf 'missing  %s\n' "$tool"
  fi
done

section "Kubernetes"
if [[ "$SKIP_CLUSTER" == "true" ]]; then
  echo "Skipped live-cluster checks because SRE_SKIP_CLUSTER=true"
elif ! have kubectl; then
  echo "kubectl not found; no cluster inspection possible"
elif ! kubectl config current-context >/dev/null 2>&1; then
  echo "kubectl present but no current context configured"
else
  echo "context: $(kubectl config current-context)"
  kubectl version 2>/dev/null | sed 's/^/version: /' || echo "server version unavailable (no connectivity?)"
  if kubectl auth can-i list namespaces >/dev/null 2>&1; then
    echo "namespaces:"
    kubectl get namespaces -o name 2>/dev/null | sed 's|namespace/|  - |' || true
  else
    echo "cannot list namespaces (limited RBAC) — ask the user for the target namespace"
  fi
  echo "node provider hint:"
  provider_id="$(kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null || true)"
  if [[ -n "$provider_id" ]]; then
    printf '  %s\n' "$provider_id"
  else
    echo "  unavailable"
  fi
fi

section "GitOps"
if [[ "$SKIP_CLUSTER" == "true" ]] || ! have kubectl || ! kubectl config current-context >/dev/null 2>&1; then
  echo "Skipped (no cluster access)"
else
  if kubectl get crd kustomizations.kustomize.toolkit.fluxcd.io >/dev/null 2>&1; then
    echo "Flux CRDs present — inspect with: flux get all -A"
  else
    echo "Flux: not detected"
  fi
  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    echo "Argo CD CRDs present — inspect with: kubectl get applications -A"
  else
    echo "Argo CD: not detected"
  fi
fi

section "Cloud"
if have aws && aws sts get-caller-identity --query Account --output text >/dev/null 2>&1; then
  echo "aws: authenticated (account $(aws sts get-caller-identity --query Account --output text 2>/dev/null))"
elif have aws; then
  echo "aws: CLI present, not authenticated"
fi
if have gcloud; then
  project="$(gcloud config list --format='value(core.project)' 2>/dev/null || true)"
  echo "gcloud: CLI present${project:+, project $project}"
fi
if have az && az account show --query name -o tsv >/dev/null 2>&1; then
  echo "az: authenticated ($(az account show --query name -o tsv 2>/dev/null))"
elif have az; then
  echo "az: CLI present, not authenticated"
fi
if ! have aws && ! have gcloud && ! have az; then
  echo "No cloud CLIs detected"
fi

#!/usr/bin/env bash
set -euo pipefail

SKIP_CLUSTER="${SRE_SKIP_CLUSTER:-false}"

usage() {
  cat <<'EOF'
Usage: sre-env-discovery.sh

Read-only environment discovery for SRE investigations. Reports available
CLI tooling, Kubernetes context, GitOps managers, EKS/GKE detection, and
cloud providers. Never mutates anything and never prints secret values.

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

cluster_reachable() {
  [[ "$SKIP_CLUSTER" != "true" ]] && have kubectl && kubectl get --raw /readyz --request-timeout=5s >/dev/null 2>&1
}

section "Tooling"
for tool in kubectl helm kustomize flux argocd git gh glab aws gcloud az terraform pulumi crossplane jq curl; do
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
elif ! kubectl get --raw /readyz --request-timeout=5s >/dev/null 2>&1; then
  echo "context: $(kubectl config current-context)"
  echo "API unreachable (expired credentials, VPN, or network) — no live-cluster evidence available"
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

section "EKS"
if ! cluster_reachable; then
  echo "Skipped (no cluster access)"
elif kubectl get daemonset aws-node -n kube-system >/dev/null 2>&1 && [[ "${provider_id:-}" == aws://* ]]; then
  echo "EKS: detected (aws-node DaemonSet present, node providerID ${provider_id:-unknown})"
else
  echo "EKS: not detected"
fi

section "GKE"
if ! cluster_reachable; then
  echo "Skipped (no cluster access)"
elif kubectl get nodes -l cloud.google.com/gke-nodepool --no-headers 2>/dev/null | grep -q . && [[ "${provider_id:-}" == gce://* ]]; then
  echo "GKE: detected (cloud.google.com/gke-nodepool label present, node providerID ${provider_id:-unknown})"
else
  echo "GKE: not detected"
fi

section "GitOps"
if ! cluster_reachable; then
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
  if kubectl get crd providers.pkg.crossplane.io >/dev/null 2>&1; then
    echo "Crossplane CRDs present — inspect with: scripts/crossplane-status-check.sh"
  else
    echo "Crossplane: not detected"
  fi
fi

section "Cloud"
if [[ "$SKIP_CLUSTER" == "true" ]]; then
  # Offline mode: report CLI presence only; the auth calls below are live
  # network round-trips (aws sts / az account) that would block or fail.
  echo "Skipped live auth checks because SRE_SKIP_CLUSTER=true"
  for cli in aws gcloud az; do
    have "$cli" && echo "$cli: CLI present (auth check skipped)"
  done
  if ! have aws && ! have gcloud && ! have az; then
    echo "No cloud CLIs detected"
  fi
else
  if have aws; then
    aws_account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
    if [[ -n "$aws_account" ]]; then
      echo "aws: authenticated (account $aws_account)"
    else
      echo "aws: CLI present, not authenticated"
    fi
  fi
  if have gcloud; then
    gcloud_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
    if [[ -n "$gcloud_account" ]]; then
      project="$(gcloud config list --format='value(core.project)' 2>/dev/null || true)"
      echo "gcloud: authenticated (account $gcloud_account)${project:+, project $project}"
    else
      echo "gcloud: CLI present, not authenticated"
    fi
  fi
  if have az; then
    az_subscription="$(az account show --query name -o tsv 2>/dev/null || true)"
    if [[ -n "$az_subscription" ]]; then
      echo "az: authenticated ($az_subscription)"
    else
      echo "az: CLI present, not authenticated"
    fi
  fi
  if ! have aws && ! have gcloud && ! have az; then
    echo "No cloud CLIs detected"
  fi
fi

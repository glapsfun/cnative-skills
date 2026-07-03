#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sre-evidence.sh <namespace> <workload>

Read-only one-shot Kubernetes evidence pack for a workload (Deployment,
StatefulSet, or label match). Collects pod state, events, previous logs,
resource usage, and rollout history. Never mutates; never prints secrets.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage
  exit 2
fi

NS="$1"
WORKLOAD="$2"

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl config current-context >/dev/null 2>&1; then
  echo "No kubectl or configured context — cannot collect evidence." >&2
  exit 1
fi

if ! kubectl get --raw /readyz --request-timeout=5s >/dev/null 2>&1; then
  echo "Cluster API unreachable (expired credentials, VPN, or network) — cannot collect evidence." >&2
  echo "Fix cluster access first (e.g. re-authenticate), then re-run." >&2
  exit 1
fi

section() {
  printf '\n## %s\n' "$1"
}

section "Pods"
kubectl get pods -n "$NS" -o wide 2>/dev/null | {
  head -1
  grep -i -- "$WORKLOAD" || echo "no pods matching '$WORKLOAD'"
} || true

section "Workload status"
kubectl get deploy,statefulset,daemonset -n "$NS" 2>/dev/null | {
  head -1
  grep -i -- "$WORKLOAD" || echo "no workload objects matching '$WORKLOAD'"
} || true
if kubectl get deploy -n "$NS" "$WORKLOAD" >/dev/null 2>&1; then
  kubectl rollout status deploy/"$WORKLOAD" -n "$NS" --timeout=5s 2>&1 || true
  echo "--- rollout history ---"
  kubectl rollout history deploy/"$WORKLOAD" -n "$NS" 2>/dev/null || true
fi

section "Recent events"
kubectl get events -n "$NS" --sort-by=.lastTimestamp 2>/dev/null | tail -30 || echo "cannot read events"

section "Describe (first matching pod)"
first_pod="$(kubectl get pods -n "$NS" -o name 2>/dev/null | grep -i -- "$WORKLOAD" | head -1 || true)"
if [[ -n "$first_pod" ]]; then
  kubectl describe -n "$NS" "$first_pod" 2>/dev/null | sed -n '/^Containers:/,/^Events:/p'
  kubectl describe -n "$NS" "$first_pod" 2>/dev/null | sed -n '/^Events:/,$p'
else
  echo "no matching pod to describe"
fi

section "Previous logs (last crashed container, tail 100)"
if [[ -n "$first_pod" ]]; then
  kubectl logs -n "$NS" "$first_pod" --previous --tail=100 2>/dev/null || echo "no previous logs (container has not restarted)"
else
  echo "no matching pod"
fi

section "Current logs (tail 50)"
if [[ -n "$first_pod" ]]; then
  kubectl logs -n "$NS" "$first_pod" --tail=50 2>/dev/null || echo "cannot read logs"
else
  echo "no matching pod"
fi

section "Resource usage"
kubectl top pod -n "$NS" 2>/dev/null | {
  head -1
  grep -i -- "$WORKLOAD" || true
} || echo "metrics-server unavailable"

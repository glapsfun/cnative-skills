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

# Bound every call so a hung or unreachable API fails fast instead of blocking
# the whole evidence pack.
kc() {
  kubectl --request-timeout=8s "$@"
}

# Best-effort reachability probe. A degraded control plane (/readyz != ok) or
# missing RBAC on cluster-scoped reads must NOT abort collection: the apiserver
# watch cache often still serves namespaced reads during exactly the incidents
# this tool is for. Warn and continue; every section degrades on its own.
if ! kc get namespace "$NS" >/dev/null 2>&1; then
  echo "Warning: cannot read namespace '$NS' (API degraded, limited RBAC, or bad name) — evidence may be partial." >&2
fi

section() {
  printf '\n## %s\n' "$1"
}

# Print the header row plus rows matching WORKLOAD (literal, case-insensitive).
# Captures the command output first so head and grep never share one pipe (a
# shared pipe lets head consume the rows grep needs, hiding the workload).
show_matching() {
  local fallback="$1" out header
  out="$(cat)"
  if [[ -z "$out" ]]; then
    printf '%s\n' "$fallback"
    return
  fi
  IFS= read -r header <<<"$out"
  printf '%s\n' "$header"
  grep -iF -- "$WORKLOAD" <<<"$out" || printf '%s\n' "$fallback"
}

section "Pods"
kc get pods -n "$NS" -o wide 2>/dev/null | show_matching "no pods matching '$WORKLOAD'" || true

section "Workload status"
kc get deploy,statefulset,daemonset -n "$NS" 2>/dev/null | show_matching "no workload objects matching '$WORKLOAD'" || true

# Rollout status/history for every Deployment/StatefulSet/DaemonSet whose name
# matches the workload argument — not just an exact-name Deployment.
workloads=()
while IFS= read -r line; do
  if [[ -n "$line" ]]; then workloads+=("$line"); fi
done < <(kc get deploy,statefulset,daemonset -n "$NS" -o name 2>/dev/null | grep -iF -- "$WORKLOAD" || true)
if [[ ${#workloads[@]} -gt 0 ]]; then
  for w in "${workloads[@]}"; do
    echo "--- rollout: $w ---"
    kc rollout status "$w" -n "$NS" --timeout=5s 2>&1 || true
    kc rollout history "$w" -n "$NS" 2>/dev/null || true
  done
fi

section "Recent events"
kc get events -n "$NS" --sort-by=.lastTimestamp 2>/dev/null | tail -30 || echo "cannot read events"

# All pods matching the workload — describe and log each so an unhealthy replica
# is never masked by a healthy one.
pods=()
while IFS= read -r line; do
  if [[ -n "$line" ]]; then pods+=("$line"); fi
done < <(kc get pods -n "$NS" -o name 2>/dev/null | grep -iF -- "$WORKLOAD" || true)

section "Describe (matching pods)"
if [[ ${#pods[@]} -gt 0 ]]; then
  for pod in "${pods[@]}"; do
    echo "--- $pod ---"
    # Describe once, then slice: the Containers-through-Events range, then the
    # Events section with its duplicate header line dropped (tail -n +2) — no
    # doubled Events: line, one API call, and portable to BSD/GNU sed. Guarded
    # so a vanished pod cannot abort the script.
    desc="$(kc describe -n "$NS" "$pod" 2>/dev/null || true)"
    printf '%s\n' "$desc" | sed -n '/^Containers:/,/^Events:/p'
    printf '%s\n' "$desc" | sed -n '/^Events:/,$p' | tail -n +2
  done
else
  echo "no pods matching '$WORKLOAD' to describe"
fi

section "Previous logs (crashed containers, tail 100)"
if [[ ${#pods[@]} -gt 0 ]]; then
  for pod in "${pods[@]}"; do
    echo "--- $pod ---"
    kc logs -n "$NS" "$pod" --previous --tail=100 2>/dev/null || echo "no previous logs (container has not restarted)"
  done
else
  echo "no matching pod"
fi

section "Current logs (tail 50)"
if [[ ${#pods[@]} -gt 0 ]]; then
  for pod in "${pods[@]}"; do
    echo "--- $pod ---"
    kc logs -n "$NS" "$pod" --tail=50 2>/dev/null || echo "cannot read logs"
  done
else
  echo "no matching pod"
fi

section "Resource usage"
kc top pod -n "$NS" 2>/dev/null | show_matching "metrics-server unavailable or no pods matching '$WORKLOAD'" || true

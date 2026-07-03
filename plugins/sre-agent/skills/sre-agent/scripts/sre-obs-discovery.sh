#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sre-obs-discovery.sh [namespace ...]

Read-only observability endpoint discovery. Searches the given namespaces
(default: all accessible) for Prometheus, Alertmanager, Grafana, and Loki
services, and lists ingress hosts that look observability-related.
Prints endpoints and port-forward commands only — never secret values.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl config current-context >/dev/null 2>&1; then
  echo "No kubectl or no configured context — cannot discover in-cluster endpoints."
  echo "Ask the user for Prometheus/Grafana/Loki URLs directly."
  exit 0
fi

ns_args=()
if [[ $# -gt 0 ]]; then
  for ns in "$@"; do
    ns_args+=("--namespace=$ns")
  done
else
  ns_args+=("--all-namespaces")
fi

section() {
  printf '\n## %s\n' "$1"
}

find_services() {
  local pattern="$1" port="$2" probe_path="$3"
  local found
  found="$(kubectl get svc "${ns_args[@]}" -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PORTS:.spec.ports[*].port' --no-headers 2>/dev/null | awk -v p="$pattern" 'tolower($2) ~ p' || true)"
  if [[ -z "$found" ]]; then
    echo "not found (searched service names matching /$pattern/)"
    return
  fi
  while read -r ns name ports; do
    printf 'svc %s/%s (ports: %s)\n' "$ns" "$name" "$ports"
    printf '  port-forward: kubectl port-forward -n %s svc/%s %s:%s\n' "$ns" "$name" "$port" "$port"
  done <<<"$found"
  printf 'probe readiness: curl -fsS localhost:%s%s\n' "$port" "$probe_path"
}

section "Prometheus"
find_services 'prometheus' 9090 '/-/ready'

section "Alertmanager"
find_services 'alertmanager' 9093 '/-/ready'

section "Grafana"
find_services 'grafana' 3000 '/api/health'

section "Loki"
find_services 'loki' 3100 '/ready'

section "Ingresses"
ingresses="$(kubectl get ingress "${ns_args[@]}" --no-headers 2>/dev/null | awk 'tolower($0) ~ /prometheus|grafana|loki|alertmanager|metrics/' || true)"
if [[ -n "$ingresses" ]]; then
  echo "$ingresses"
else
  echo "no observability-related ingresses found"
fi

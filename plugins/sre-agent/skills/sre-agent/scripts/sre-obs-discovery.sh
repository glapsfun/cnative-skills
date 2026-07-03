#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sre-obs-discovery.sh [namespace ...]

Read-only observability endpoint discovery. Searches the given namespaces
(default: all accessible) for Prometheus, Alertmanager, Grafana, Loki, Mimir,
and Tempo services, and lists ingress hosts that look observability-related.
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

if ! kubectl get --raw /readyz --request-timeout=5s >/dev/null 2>&1; then
  echo "Cluster API unreachable (expired credentials, VPN, or network) — cannot discover endpoints."
  echo "Fix cluster access first, or ask the user for Prometheus/Grafana/Loki URLs directly."
  exit 0
fi

# Requested namespaces (empty => all accessible namespaces).
NAMESPACES=("$@")

section() {
  printf '\n## %s\n' "$1"
}

# List services (NS NAME PORTS) whose name matches $pattern across the requested
# namespaces. kubectl honors only the LAST --namespace flag, so each namespace
# must be queried on its own instead of stacking flags.
match_services() {
  local pattern="$1" ns out
  if [[ ${#NAMESPACES[@]} -gt 0 ]]; then
    for ns in "${NAMESPACES[@]}"; do
      out="$(kubectl get svc --namespace="$ns" -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PORTS:.spec.ports[*].port' --no-headers 2>/dev/null | awk -v p="$pattern" 'tolower($2) ~ p' || true)"
      if [[ -n "$out" ]]; then printf '%s\n' "$out"; fi
    done
  else
    kubectl get svc --all-namespaces -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PORTS:.spec.ports[*].port' --no-headers 2>/dev/null | awk -v p="$pattern" 'tolower($2) ~ p' || true
  fi
}

find_services() {
  local pattern="$1" port="$2" probe_path="$3"
  local found ns name ports svc_port
  found="$(match_services "$pattern")"
  if [[ -z "$found" ]]; then
    echo "not found (searched service names matching /$pattern/)"
    return
  fi
  while read -r ns name ports; do
    [[ -z "$ns" ]] && continue
    # Map the well-known local port to the service's ACTUAL exposed port (first
    # one, if several); a hardcoded remote port fails when the Service differs
    # from the default (e.g. Grafana on 80).
    svc_port="${ports%%,*}"
    printf 'svc %s/%s (ports: %s)\n' "$ns" "$name" "$ports"
    printf '  port-forward: kubectl port-forward -n %s svc/%s %s:%s\n' "$ns" "$name" "$port" "${svc_port:-$port}"
  done <<<"$found"
  printf 'probe readiness (after port-forward): curl -fsS localhost:%s%s\n' "$port" "$probe_path"
}

section "Prometheus"
find_services 'prometheus' 9090 '/-/ready'

section "Alertmanager"
find_services 'alertmanager' 9093 '/-/ready'

section "Grafana"
find_services 'grafana' 3000 '/api/health'

section "Loki"
find_services 'loki' 3100 '/ready'

section "Mimir"
find_services 'mimir' 9009 '/ready'

section "Tempo"
find_services 'tempo' 3200 '/ready'

section "Ingresses"
ingresses=""
if [[ ${#NAMESPACES[@]} -gt 0 ]]; then
  for ns in "${NAMESPACES[@]}"; do
    out="$(kubectl get ingress --namespace="$ns" --no-headers 2>/dev/null | awk 'tolower($0) ~ /prometheus|grafana|loki|alertmanager|mimir|tempo|metrics/' || true)"
    if [[ -n "$out" ]]; then ingresses+="$out"$'\n'; fi
  done
else
  ingresses="$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | awk 'tolower($0) ~ /prometheus|grafana|loki|alertmanager|mimir|tempo|metrics/' || true)"
fi
if [[ -n "${ingresses//[$'\n']/}" ]]; then
  printf '%s' "$ingresses"
else
  echo "no observability-related ingresses found"
fi

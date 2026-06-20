#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
APP=""
DEST_NAMESPACE=""
INCLUDE_LOGS="false"
TAIL_LINES="${ARGOCD_LOG_TAIL:-120}"

usage() {
  cat <<'EOF'
Usage: argocd-diagnostics.sh [--app <name>] [--namespace <argocd-namespace>] [--dest-namespace <namespace>] [--logs]

Collect read-only Argo CD diagnostics.

Modes:
  No --app       Collect broad control-plane, repository, cluster, and app inventory.
  --app <name>  Collect app-specific status, diff, resources, Application CR, and optional destination namespace state.

Options:
  --app <name>                  Argo CD Application name
  --namespace <namespace>       Argo CD control-plane namespace (default: argocd)
  --dest-namespace <namespace>  Workload destination namespace for pod/job/event context
  --logs                        Include recent application-controller and repo-server logs
  -h, --help                    Show this help

Safety:
  This script does not run sync, delete, terminate-op, patch, apply, or any other mutating command.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP="${2:-}"
      shift 2
      ;;
    --namespace|-n)
      ARGOCD_NAMESPACE="${2:-}"
      shift 2
      ;;
    --dest-namespace)
      DEST_NAMESPACE="${2:-}"
      shift 2
      ;;
    --logs)
      INCLUDE_LOGS="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${ARGOCD_NAMESPACE}" ]]; then
  echo "Argo CD namespace cannot be empty" >&2
  exit 2
fi

section() {
  printf '\n## %s\n' "$1"
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@" 2>&1 || {
    status=$?
    echo "Command exited with status ${status}; continuing diagnostics" >&2
    return 0
  }
}

have_argocd() {
  command -v argocd >/dev/null 2>&1
}

argocd_has_server() {
  [[ -n "${ARGOCD_SERVER:-}" ]] || argocd context >/dev/null 2>&1
}

kubectl_has_context() {
  command -v kubectl >/dev/null 2>&1 && kubectl config current-context >/dev/null 2>&1
}

kubectl_can_reach_api() {
  kubectl_has_context && kubectl version --request-timeout=5s >/dev/null 2>&1
}

section "Tool context"
if have_argocd; then
  run argocd version --client
  if argocd_has_server; then
    run argocd context
  else
    echo "argocd server context: unavailable; set ARGOCD_SERVER or run argocd login for server-side CLI diagnostics"
  fi
else
  echo "argocd CLI: not found"
fi

if kubectl_has_context; then
  echo "kubectl context: $(kubectl config current-context)"
  if ! kubectl_can_reach_api; then
    echo "kubectl API: unreachable"
  fi
else
  echo "kubectl context: unavailable"
fi

if [[ -n "${APP}" ]]; then
  section "Argo CD application: ${APP}"
  if have_argocd && argocd_has_server; then
    run argocd app get "${APP}" --show-operation
    run argocd app resources "${APP}"
    run argocd app diff "${APP}"
  else
    echo "Skipping argocd app commands because argocd CLI/server context is unavailable"
  fi

  if kubectl_can_reach_api; then
    section "Application custom resource"
    run kubectl describe application "${APP}" -n "${ARGOCD_NAMESPACE}"
    run kubectl get application "${APP}" -n "${ARGOCD_NAMESPACE}" -o yaml
  fi
else
  section "Argo CD inventory"
  if have_argocd && argocd_has_server; then
    run argocd app list
    run argocd proj list
    run argocd repo list
    run argocd cluster list
  else
    echo "Skipping argocd inventory because argocd CLI/server context is unavailable"
  fi

  if kubectl_can_reach_api; then
    section "Argo CD custom resources"
    run kubectl get applications.argoproj.io -A
    run kubectl get appprojects.argoproj.io -n "${ARGOCD_NAMESPACE}"
    run kubectl get applicationsets.argoproj.io -n "${ARGOCD_NAMESPACE}"
  fi
fi

if kubectl_can_reach_api; then
  section "Control plane state"
  run kubectl -n "${ARGOCD_NAMESPACE}" get deploy,statefulset,pod,svc,cm
  run kubectl -n "${ARGOCD_NAMESPACE}" get events --sort-by=.lastTimestamp

  if [[ -n "${DEST_NAMESPACE}" ]]; then
    section "Destination namespace: ${DEST_NAMESPACE}"
    run kubectl -n "${DEST_NAMESPACE}" get deploy,statefulset,daemonset,job,pod,svc,ingress
    run kubectl -n "${DEST_NAMESPACE}" get events --sort-by=.lastTimestamp
  fi

  if [[ "${INCLUDE_LOGS}" == "true" ]]; then
    section "Recent controller logs"
    run kubectl -n "${ARGOCD_NAMESPACE}" logs deploy/argocd-application-controller --tail="${TAIL_LINES}"
    run kubectl -n "${ARGOCD_NAMESPACE}" logs deploy/argocd-repo-server --tail="${TAIL_LINES}"
  fi
else
  echo "Skipping kubectl diagnostics because kubectl is unavailable or the API is unreachable"
fi

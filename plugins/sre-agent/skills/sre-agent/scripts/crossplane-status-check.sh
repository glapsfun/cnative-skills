#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: crossplane-status-check.sh [TYPE[.VERSION][.GROUP][/NAME]]

Read-only Crossplane health classifier for SRE Agent Phase 3/4 evidence
gathering and Phase 5/6 remediation verification.

No argument: cluster-wide sweep. Classifies every Provider from
`kubectl get providers.pkg.crossplane.io -o json` (Installed/Healthy
conditions) and every Managed/Composite Resource from `kubectl get managed
-A -o json` (Ready/Synced conditions).

With TYPE[/NAME]: scopes the resource classification to that resource's
tree via `crossplane resource trace TYPE[/NAME] -o json` when the
`crossplane` CLI is on PATH (Providers are still checked cluster-wide).
When the `crossplane` CLI is not on PATH, falls back to the cluster-wide
Managed Resource sweep and notes that per-resource scoping is unavailable.

Never mutates anything - kubectl get and `crossplane resource trace` are
both read-only.

Exit codes:
  0  All Providers report Installed=True/Healthy=True and all classified
     resources report Ready=True/Synced=True.
  1  At least one unhealthy Provider or resource is present - every one is
     listed with kind/namespace/name and the offending condition(s).
  2  Usage error (more than one positional argument, or an unrecognized
     flag).
  3  Environment error - kubectl or jq missing, the cluster is unreachable,
     no Crossplane CRDs are installed, or `crossplane resource trace`
     itself failed.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

resource_ref="${1:-}"
if [[ $# -gt 1 ]]; then
  echo "crossplane-status-check.sh accepts at most one argument: [TYPE[.VERSION][.GROUP][/NAME]]" >&2
  usage
  exit 2
fi
if [[ -n "$resource_ref" && "$resource_ref" == -* ]]; then
  echo "unrecognized flag: $resource_ref" >&2
  usage
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }

if ! have kubectl; then
  echo "GAP: kubectl not found on PATH - install it or run this against a cluster where it's available" >&2
  exit 3
fi

if ! have jq; then
  echo "GAP: jq not found on PATH - required to classify Crossplane status output" >&2
  exit 3
fi

if ! kubectl get --raw /readyz --request-timeout=5s >/dev/null 2>&1; then
  echo "GAP: Kubernetes API unreachable (expired credentials, VPN, or network) - no live Crossplane evidence available" >&2
  exit 3
fi

if ! kubectl get crd providers.pkg.crossplane.io >/dev/null 2>&1; then
  echo "GAP: Crossplane CRDs not found on this cluster (providers.pkg.crossplane.io missing) - Crossplane is not installed here" >&2
  exit 3
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# --- Providers: always checked cluster-wide -------------------------------
providers_json="$work_dir/providers.json"
if ! kubectl get providers.pkg.crossplane.io -o json >"$providers_json"; then
  echo "GAP: 'kubectl get providers.pkg.crossplane.io' failed - see output above" >&2
  exit 3
fi

provider_unhealthy="$(
  jq -r '
    (.items // [])[]
    | . as $p
    | ($p.status.conditions // [])
      | map(select(.type=="Installed" or .type=="Healthy") | select(.status != "True"))
      | if length > 0 then
          "\($p.metadata.name)\t" + (map("\(.type)=\(.status) (\(.reason))") | join(", "))
        else empty end
  ' "$providers_json"
)"

# --- Resources: scoped trace tree, or cluster-wide managed sweep ---------
scope_note=""
resource_unhealthy=""

classify_managed_json() {
  # $1: path to a `kubectl get managed -A -o json` style document with a
  # top-level .items array.
  jq -r '
    (.items // [.])[]
    | . as $r
    | ($r.status.conditions // [])
      | map(select(.type=="Ready" or .type=="Synced") | select(.status != "True"))
      | if length > 0 then
          "\($r.kind)/\($r.metadata.name)" +
          (if $r.metadata.namespace then " -n \($r.metadata.namespace)" else "" end) +
          "\t" + (map("\(.type)=\(.status) (\(.reason))") | join(", "))
        else empty end
  ' "$1"
}

classify_trace_json() {
  # $1: path to a `crossplane resource trace TYPE/NAME -o json` document -
  # a tree of {"object": <k8s object>, "children": [...]}.
  jq -r '
    def flatten_tree:
      [., (.children[]? | flatten_tree)] | flatten;
    flatten_tree
    | map(select(. != null))
    | .[]
    | . as $n
    | ($n.object.status.conditions // [])
      | map(select(.type=="Ready" or .type=="Synced") | select(.status != "True"))
      | if length > 0 then
          "\($n.object.kind)/\($n.object.metadata.name)" +
          (if $n.object.metadata.namespace then " -n \($n.object.metadata.namespace)" else "" end) +
          "\t" + (map("\(.type)=\(.status) (\(.reason))") | join(", "))
        else empty end
  ' "$1"
}

if [[ -n "$resource_ref" ]]; then
  if have crossplane; then
    trace_json="$work_dir/trace.json"
    if ! crossplane resource trace "$resource_ref" -o json >"$trace_json" 2>"$work_dir/trace.err"; then
      echo "GAP: 'crossplane resource trace $resource_ref' failed:" >&2
      cat "$work_dir/trace.err" >&2
      exit 3
    fi
    scope_note="resource tree for $resource_ref (via crossplane resource trace)"
    resource_unhealthy="$(classify_trace_json "$trace_json")"
  else
    scope_note="cluster-wide (crossplane CLI not on PATH - per-resource scoping for $resource_ref unavailable)"
    managed_json="$work_dir/managed.json"
    kubectl get managed -A -o json >"$managed_json"
    resource_unhealthy="$(classify_managed_json "$managed_json")"
  fi
else
  scope_note="cluster-wide"
  managed_json="$work_dir/managed.json"
  kubectl get managed -A -o json >"$managed_json"
  resource_unhealthy="$(classify_managed_json "$managed_json")"
fi

echo "CROSSPLANE STATUS CHECK: $scope_note"

if [[ -n "$provider_unhealthy" ]]; then
  echo
  echo "⚠ UNHEALTHY PROVIDERS:"
  while IFS= read -r line; do
    printf '  %s\n' "$line"
  done <<<"$provider_unhealthy"
fi

if [[ -n "$resource_unhealthy" ]]; then
  echo
  echo "⚠ UNHEALTHY RESOURCES:"
  while IFS= read -r line; do
    printf '  %s\n' "$line"
  done <<<"$resource_unhealthy"
fi

if [[ -n "$provider_unhealthy" || -n "$resource_unhealthy" ]]; then
  exit 1
fi

echo "All Providers and classified Managed/Composite Resources report healthy conditions."
exit 0

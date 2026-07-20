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

With TYPE[/NAME]: scopes the resource classification via `crossplane
resource trace TYPE[/NAME] -o json` when the `crossplane` CLI is on PATH
(Providers are still checked cluster-wide). A NAME scopes to that single
resource's tree; TYPE alone lists every resource of that kind. When the
`crossplane` CLI is not on PATH, falls back to the cluster-wide Managed
Resource sweep and notes that per-resource scoping is unavailable.

A resource missing its Ready or Synced condition entirely (not yet
reconciled, or a kind that never sets one) is reported as unhealthy too,
not silently treated as healthy - "no evidence of health" is not health.

Never mutates anything - kubectl get and `crossplane resource trace` are
both read-only.

Exit codes:
  0  All Providers report Installed=True/Healthy=True and all classified
     resources report Ready=True/Synced=True.
  1  At least one unhealthy or not-yet-reporting Provider or resource is
     present - every one is listed with kind/namespace/name and the
     offending or missing condition(s).
  2  Usage error (more than one positional argument, or an unrecognized
     flag).
  3  Environment error - kubectl or jq missing, the cluster is unreachable,
     no Crossplane CRDs are installed, a kubectl/crossplane call failed, or
     its output could not be parsed as JSON.
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

if ! kubectl get crd providers.pkg.crossplane.io --request-timeout=15s >/dev/null 2>&1; then
  echo "GAP: Crossplane CRDs not found on this cluster (providers.pkg.crossplane.io missing) - Crossplane is not installed here" >&2
  exit 3
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Shared jq fragment: given $kind/$name/$namespace/$conditions, emits one
# "kind/name -n ns\ttype=status (reason), ..." line when a Ready or Synced
# condition is unhealthy (status != "True") OR missing entirely. Reused by
# both the Provider check (Installed/Healthy) and the resource check
# (Ready/Synced) below, and by both resource data sources (a flat kubectl
# list, and a crossplane resource trace tree) so the classification logic
# is defined exactly once.
read -r -d '' jq_classify_def <<'JQ_EOF' || true
def classify($kind; $name; $namespace; $watched; $conditions):
  ($conditions // []) as $all
  | ($watched - ($all | map(.type))) as $missing
  | ($all | map(select(.type as $t | $watched | index($t)) | select(.status != "True"))) as $bad
  | if ($missing | length) > 0 or ($bad | length) > 0 then
      "\($kind)/\($name)" + (if $namespace then " -n \($namespace)" else "" end) +
      "\t" + (
        ($bad | map("\(.type)=\(.status) (\(.reason // "no reason given"))")) +
        ($missing | map("\(.)=<missing>"))
        | join(", ")
      )
    else empty end;
JQ_EOF

# --- Providers: always checked cluster-wide -------------------------------
providers_json="$work_dir/providers.json"
if ! kubectl get providers.pkg.crossplane.io -o json --request-timeout=15s >"$providers_json"; then
  echo "GAP: 'kubectl get providers.pkg.crossplane.io' failed - see output above" >&2
  exit 3
fi

if ! provider_unhealthy="$(
  jq -r "
    $jq_classify_def
    (.items // [])[]
    | classify(.kind; .metadata.name; .metadata.namespace; [\"Installed\",\"Healthy\"]; .status.conditions)
  " "$providers_json"
)"; then
  echo "GAP: failed to parse 'kubectl get providers.pkg.crossplane.io' JSON output" >&2
  exit 3
fi

# --- Resources: scoped trace tree, or cluster-wide managed sweep ---------
#
# `kubectl get managed -A -o json` always returns a flat `{items: [...]}`
# list of raw Kubernetes objects. `crossplane resource trace TYPE[/NAME]
# -o json` returns either a single `{object, children}` tree (NAME given)
# or a flat `{items: [...]}` list of such trees (TYPE only, no NAME) - both
# shapes are normalized to a stream of raw Kubernetes objects below before
# classification, so the same shared jq_classify_def applies to either
# source.
# shellcheck disable=SC2016  # single quotes are intentional; $r is a jq variable, not a shell one
jq_program_managed='
'"$jq_classify_def"'
(.items // [.])[] as $r
| classify($r.kind; $r.metadata.name; $r.metadata.namespace; ["Ready","Synced"]; $r.status.conditions)
'

# shellcheck disable=SC2016  # single quotes are intentional; $r is a jq variable, not a shell one
jq_program_trace='
def flatten_tree:
  [., (.children[]? | flatten_tree)] | flatten;
def roots:
  if has("items") then (.items // [])[] else . end;
'"$jq_classify_def"'
roots
| flatten_tree
| map(select(. != null))
| .[]
| .object as $r
| classify($r.kind; $r.metadata.name; $r.metadata.namespace; ["Ready","Synced"]; $r.status.conditions)
'

fetch_managed_sweep() {
  local managed_json="$work_dir/managed.json"
  if ! kubectl get managed -A -o json --request-timeout=15s >"$managed_json"; then
    echo "GAP: 'kubectl get managed -A -o json' failed - see output above" >&2
    exit 3
  fi
  if ! resource_unhealthy="$(jq -r "$jq_program_managed" "$managed_json")"; then
    echo "GAP: failed to parse 'kubectl get managed -A' JSON output" >&2
    exit 3
  fi
}

scope_note=""
resource_unhealthy=""

if [[ -n "$resource_ref" ]] && have crossplane; then
  trace_json="$work_dir/trace.json"
  if ! crossplane resource trace "$resource_ref" -o json >"$trace_json" 2>"$work_dir/trace.err"; then
    echo "GAP: 'crossplane resource trace $resource_ref' failed:" >&2
    cat "$work_dir/trace.err" >&2
    exit 3
  fi
  scope_note="resource tree for $resource_ref (via crossplane resource trace)"
  if ! resource_unhealthy="$(jq -r "$jq_program_trace" "$trace_json")"; then
    echo "GAP: failed to parse 'crossplane resource trace $resource_ref' JSON output" >&2
    exit 3
  fi
elif [[ -n "$resource_ref" ]]; then
  scope_note="cluster-wide (crossplane CLI not on PATH - per-resource scoping for $resource_ref unavailable)"
  fetch_managed_sweep
else
  scope_note="cluster-wide"
  fetch_managed_sweep
fi

echo "CROSSPLANE STATUS CHECK: $scope_note"

print_unhealthy_section() {
  local header="$1" content="$2"
  [[ -n "$content" ]] || return 0
  echo
  echo "$header"
  while IFS= read -r line; do
    printf '  %s\n' "$line"
  done <<<"$content"
}

print_unhealthy_section "⚠ UNHEALTHY PROVIDERS:" "$provider_unhealthy"
print_unhealthy_section "⚠ UNHEALTHY RESOURCES:" "$resource_unhealthy"

if [[ -n "$provider_unhealthy" || -n "$resource_unhealthy" ]]; then
  exit 1
fi

echo "All Providers and classified Managed/Composite Resources report healthy conditions."
exit 0

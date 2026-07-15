#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sre-snapshot.sh snapshot <namespace> [repo-path]
  sre-snapshot.sh diff <before-file> <after-file>

Read-only state fingerprint for SRE Agent Phase 3 mutation verification.

`snapshot` prints a deterministic, sorted fingerprint of spec-bearing
Kubernetes objects in <namespace> - Deployments, StatefulSets, DaemonSets,
ConfigMaps, Secrets, Services, HorizontalPodAutoscalers, and
PodDisruptionBudgets - plus, when [repo-path] is given, its git HEAD SHA and
working-tree cleanliness. Never touches secret values: Secrets are
fingerprinted by their data KEY NAMES only, via kubectl's
`{range $k,$v := .data}{$k}{"\n"}{end}` idiom - $v is bound but never
referenced, so no secret value is ever read into this script's output.

`diff` compares two snapshot files and reports every ADDED/REMOVED/CHANGED
line between them.

Exit codes:
  0  No difference - no mutation detected.
  1  A difference was found - treat it as a caught mutation.
  2  Usage error.

Never mutates. Degrades gracefully: a missing kubectl/cluster/git produces a
snapshot with fewer lines (or none), never a hard failure.
EOF
}

KINDS=(deployment statefulset daemonset configmap service horizontalpodautoscaler poddisruptionbudget)

have() { command -v "$1" >/dev/null 2>&1; }

sha256() {
  if have sha256sum; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

snapshot_kind() {
  local kind="$1" ns="$2" names name spec hash
  have kubectl || return 0
  names="$(kubectl get "$kind" -n "$ns" -o name 2>/dev/null || true)"
  [[ -z "$names" ]] && return 0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    spec="$(kubectl get "$name" -n "$ns" -o jsonpath='{.spec}' 2>/dev/null || true)"
    hash="$(printf '%s' "$spec" | sha256)"
    printf 'K8S %s %s\n' "$name" "$hash"
  done <<<"$names"
}

snapshot_secrets() {
  local ns="$1" names name keys hash
  have kubectl || return 0
  names="$(kubectl get secret -n "$ns" -o name 2>/dev/null || true)"
  [[ -z "$names" ]] && return 0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    keys="$(kubectl get "$name" -n "$ns" -o jsonpath='{range $k,$v := .data}{$k}{"\n"}{end}' 2>/dev/null | sort | paste -sd, - || true)"
    hash="$(printf '%s' "$keys" | sha256)"
    printf 'K8S %s %s\n' "$name" "$hash"
  done <<<"$names"
}

snapshot_git() {
  local repo="$1" head porcelain hash
  have git || return 0
  [[ -d "$repo/.git" ]] || return 0
  head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)"
  porcelain="$(git -C "$repo" status --porcelain 2>/dev/null || true)"
  hash="$(printf '%s' "$porcelain" | sha256)"
  printf 'GIT HEAD %s\n' "$head"
  printf 'GIT PORCELAIN %s\n' "$hash"
}

cmd_snapshot() {
  local ns="${1:-}" repo="${2:-}" kind
  if [[ -z "$ns" ]]; then
    echo "snapshot requires <namespace>" >&2
    usage
    exit 2
  fi
  {
    for kind in "${KINDS[@]}"; do
      snapshot_kind "$kind" "$ns"
    done
    snapshot_secrets "$ns"
    if [[ -n "$repo" ]]; then
      snapshot_git "$repo"
    fi
  } | sort
}

cmd_diff() {
  local before="${1:-}" after="${2:-}"
  if [[ -z "$before" || -z "$after" ]]; then
    echo "diff requires <before-file> <after-file>" >&2
    usage
    exit 2
  fi
  if [[ ! -f "$before" || ! -f "$after" ]]; then
    echo "diff: both files must exist" >&2
    exit 2
  fi
  awk '
    NR == FNR { b[$1 " " $2] = $3; next }
    {
      a[$1 " " $2] = $3
      key = $1 " " $2
      if (!(key in b)) { print "ADDED", $1, $2, $3; found = 1 }
      else if (b[key] != $3) { print "CHANGED", $1, $2, b[key], $3; found = 1 }
    }
    END {
      for (key in b) {
        if (!(key in a)) {
          split(key, parts, " ")
          print "REMOVED", parts[1], parts[2], b[key]
          found = 1
        }
      }
      exit found ? 1 : 0
    }
  ' "$before" "$after"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

case "${1:-}" in
  snapshot)
    shift
    cmd_snapshot "$@"
    ;;
  diff)
    shift
    cmd_diff "$@"
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    echo "unknown subcommand: $1" >&2
    usage
    exit 2
    ;;
esac

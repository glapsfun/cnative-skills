#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pulumi-preview-check.sh <stack-dir> [pulumi preview args...]

Read-only Pulumi preview classifier for SRE Agent Phase 5/6 remediation.

Runs `pulumi preview --json` against <stack-dir> via `pulumi -C
<stack-dir>` (the script never changes its own working directory, and
never runs `pulumi stack select` - it uses whichever stack is already
selected there). Extra arguments (e.g. --config-file=..., -c key=value,
--target=<urn>) are passed through to `pulumi preview` unchanged.

Classifies the result via the JSON output's own `changeSummary` object
(Pulumi computes the op-count summary itself, unlike Terraform, whose plan
JSON has no equivalent precomputed summary) into
same/create/update/delete/replace/create-replacement/delete-replaced
counts, and lists every URN from `.steps[]` whose `op` is exactly "delete",
"replace", "create-replacement", or "delete-replaced" - the destructive
subset, excluding non-mutating bookkeeping ops like "read-replacement" or
"discard-replaced" that can appear after a previously interrupted update.

Never mutates infrastructure - `pulumi preview` is read-only.

Exit codes:
  0  Preview succeeded, no delete or replace among the changes.
  1  Preview succeeded, but at least one delete or replace is present -
     treat as high-risk and surface every listed URN before approval.
  2  Usage error (missing/invalid <stack-dir>, or no Pulumi.yaml there).
  3  Environment error - pulumi/jq missing, or `pulumi preview` itself
     failed (including "no stack selected").
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

stack_dir="${1:-}"
if [[ -z "$stack_dir" ]]; then
  echo "pulumi-preview-check.sh requires <stack-dir>" >&2
  usage
  exit 2
fi
shift

if [[ ! -d "$stack_dir" ]]; then
  echo "not a directory: $stack_dir" >&2
  exit 2
fi

if [[ ! -f "$stack_dir/Pulumi.yaml" ]]; then
  echo "no Pulumi.yaml found in: $stack_dir" >&2
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }

if ! have pulumi; then
  echo "pulumi not found on PATH - install it or use the IaC repo's own tooling" >&2
  exit 3
fi

if ! have jq; then
  echo "jq not found on PATH - required to classify preview output" >&2
  exit 3
fi

if ! work_dir="$(mktemp -d)"; then
  echo "mktemp failed - could not create a temp directory" >&2
  exit 3
fi
trap 'rm -rf "$work_dir"' EXIT
json_file="$work_dir/preview.json"

if ! pulumi -C "$stack_dir" preview --json "$@" >"$json_file"; then
  echo "pulumi preview failed - see output above" >&2
  exit 3
fi

if ! summary="$(
  jq -r '
    (.changeSummary // {})
    | to_entries
    | sort_by(.key)
    | .[]
    | "\(.key)\t\(.value)"
  ' "$json_file"
)"; then
  echo "failed to parse pulumi preview JSON output" >&2
  exit 3
fi

if ! destructive="$(
  jq -r '
    (.steps // [])[]
    | select(.op | IN("delete", "replace", "create-replacement", "delete-replaced"))
    | .urn
  ' "$json_file"
)"; then
  echo "failed to parse pulumi preview JSON output" >&2
  exit 3
fi

echo "PULUMI PREVIEW CLASSIFICATION: $stack_dir"
if [[ -n "$summary" ]]; then
  printf '%s\n' "$summary"
else
  printf 'same\t0\n'
fi

if [[ -n "$destructive" ]]; then
  echo
  echo "⚠ DESTRUCTIVE CHANGE - delete or replace present:"
  while IFS= read -r urn; do
    printf '  %s\n' "$urn"
  done <<<"$destructive"
  exit 1
fi

exit 0

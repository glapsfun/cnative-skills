#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: terraform-plan-check.sh <tf-dir> [terraform plan args...]

Read-only Terraform plan classifier for SRE Agent Phase 5/6 remediation.

Runs `terraform plan` in <tf-dir> (already-initialized: this script never
runs `terraform init`), converts the plan to JSON via `terraform show
-json`, and classifies every resource_changes entry into no-op / create /
update / delete / replace (reported as `delete,create`). Extra arguments
(e.g. -var-file=prod.tfvars, -target=..., a workspace already selected via
`terraform workspace select`) are passed through to `terraform plan`
unchanged.

Never mutates infrastructure - `terraform plan` and `terraform show` are
both read-only. The generated plan file is written under a private temp
directory and removed on exit; it is never left on disk (plan output can
contain sensitive values in cleartext).

Exit codes:
  0  Plan succeeded, no delete or replace among the changes.
  1  Plan succeeded, but at least one delete or replace is present -
     treat as high-risk and surface every listed address before approval.
  2  Usage error (missing/invalid <tf-dir>).
  3  Environment error - terraform/jq missing, <tf-dir> not initialized,
     or `terraform plan`/`terraform show` failed.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tf_dir="${1:-}"
if [[ -z "$tf_dir" ]]; then
  echo "terraform-plan-check.sh requires <tf-dir>" >&2
  usage
  exit 2
fi
shift

if [[ ! -d "$tf_dir" ]]; then
  echo "not a directory: $tf_dir" >&2
  exit 2
fi

shopt -s nullglob
tf_files=("$tf_dir"/*.tf)
shopt -u nullglob
if [[ ${#tf_files[@]} -eq 0 ]]; then
  echo "no .tf files found in: $tf_dir" >&2
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }

if ! have terraform; then
  echo "terraform not found on PATH - install it or use the IaC repo's own tooling" >&2
  exit 3
fi

if ! have jq; then
  echo "jq not found on PATH - required to classify plan output" >&2
  exit 3
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
plan_file="$work_dir/plan.tfplan"
json_file="$work_dir/plan.json"

if ! terraform -chdir="$tf_dir" plan -input=false -no-color -out="$plan_file" "$@" >&2; then
  echo "terraform plan failed - see output above" >&2
  exit 3
fi

if ! terraform -chdir="$tf_dir" show -json "$plan_file" >"$json_file"; then
  echo "terraform show -json failed" >&2
  exit 3
fi

summary="$(
  jq -r '
    (.resource_changes // [])
    | map(.change.actions | join(","))
    | group_by(.)
    | map({action: .[0], count: length})
    | sort_by(.action)
    | .[]
    | "\(.action)\t\(.count)"
  ' "$json_file"
)"

destructive="$(
  jq -r '
    (.resource_changes // [])[]
    | select(.change.actions | index("delete"))
    | .address
  ' "$json_file"
)"

echo "TERRAFORM PLAN CLASSIFICATION: $tf_dir"
if [[ -n "$summary" ]]; then
  printf '%s\n' "$summary"
else
  printf 'no-op\t0\n'
fi

if [[ -n "$destructive" ]]; then
  echo
  echo "⚠ DESTRUCTIVE CHANGE - delete or replace present:"
  while IFS= read -r addr; do
    printf '  %s\n' "$addr"
  done <<<"$destructive"
  exit 1
fi

exit 0

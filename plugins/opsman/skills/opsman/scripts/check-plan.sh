#!/bin/sh
# Structural checks for plan.yaml: shape, unique ids, resolvable deps, acyclic.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/json.sh"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  printf 'usage: check-plan.sh <plan-file>\n'
  exit 0
fi
if [ $# -ne 1 ]; then
  printf 'usage: check-plan.sh <plan-file>\n' >&2
  exit "$EX_USAGE"
fi

need_cmd jq
plan=$1
[ -f "$plan" ] || die "$EX_ARTIFACT" "plan file missing: $plan"
json_valid "$plan" || die "$EX_ARTIFACT" "plan is not valid JSON: $plan"

fail=0
problem() {
  log_error "$1"
  fail=1
}

jq -e '.steps | type == "array" and length > 0' "$plan" >/dev/null 2>&1 \
  || problem "plan.steps must be a non-empty array"

if [ "$fail" -eq 0 ]; then
  jq -e 'all(.steps[]; has("id") and has("uses") and has("depends_on")
             and has("risk") and has("success") and (.depends_on | type == "array"))' \
    "$plan" >/dev/null 2>&1 \
    || problem "every step needs id, uses, depends_on (array), risk, success"
  jq -e '(.steps | map(.id) | length) == (.steps | map(.id) | unique | length)' \
    "$plan" >/dev/null 2>&1 \
    || problem "step ids must be unique"
  jq -e '(.steps | map(.id)) as $ids
         | all(.steps[].depends_on[]?; . as $d | ($ids | index($d)) != null)' \
    "$plan" >/dev/null 2>&1 \
    || problem "every depends_on must reference an existing step id"
  jq -e 'all(.steps[]; .risk | type == "string" and test("^R[0-4]$"))' \
    "$plan" >/dev/null 2>&1 \
    || problem "every step risk must be R0..R4"
  jq -e '
    {rem: .steps, done: []}
    | until(
        (.rem | length) == 0
        or (.done as $d | (.rem | map(select(.depends_on - $d == [])) | length) == 0);
        .done as $d
        | (.rem | map(select(.depends_on - $d == [])) | map(.id)) as $ready
        | {rem: (.rem | map(select(.id as $i | ($ready | index($i)) == null))),
           done: ($d + $ready)})
    | (.rem | length) == 0
  ' "$plan" >/dev/null 2>&1 \
    || problem "dependency graph has a cycle"
fi

[ "$fail" -eq 0 ] || exit "$EX_ARTIFACT"
log_info "plan ok: $plan"

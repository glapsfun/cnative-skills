#!/bin/sh
# Runs acceptance checks through the evidence collector.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/evidence.sh"

usage() {
  printf 'usage: run-tests.sh --run <run-id>\n' >&2
}

run_id=''
while [ $# -gt 0 ]; do
  case $1 in
    --run)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      run_id=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit "$EX_USAGE"
      ;;
  esac
done
[ -n "$run_id" ] || {
  usage
  exit "$EX_USAGE"
}

need_cmd jq
run_dir=$OPSMAN_RUNS_DIR/$run_id
[ -f "$run_dir/state.json" ] || die "$EX_ARTIFACT" "no such run: $run_id"
# Guard the state BEFORE executing anything: record-event would refuse
# AcceptanceChecked afterwards, leaving real side effects with zero trace.
status=$(jq -r '.status' "$run_dir/state.json")
[ "$status" = "VALIDATING" ] \
  || die "$EX_STATE" "run $run_id is in $status; validate requires VALIDATING"
[ -f "$run_dir/acceptance.yaml" ] || die "$EX_ARTIFACT" "acceptance.yaml missing"
jq -e '.checks | type == "array" and length > 0' "$run_dir/acceptance.yaml" >/dev/null \
  || die "$EX_ARTIFACT" "acceptance.yaml must contain checks[]"

failures=0
jq -c '.checks[]' "$run_dir/acceptance.yaml" | while IFS= read -r check; do
  id=$(printf '%s\n' "$check" | jq -r '.id')
  cmd=$(printf '%s\n' "$check" | jq -r '.command')
  expected=$(printf '%s\n' "$check" | jq -r '.expected_exit')
  risk=$(printf '%s\n' "$check" | jq -r '.risk // "R0"')
  rel_cwd=$(printf '%s\n' "$check" | jq -r '.cwd // "."')
  policy=$("$SCRIPT_DIR/policy-check.sh" --risk "$risk" --command "$cmd")
  effective=$(printf '%s\n' "$policy" | jq -r '.effective_risk')
  approval_required=$(printf '%s\n' "$policy" | jq -r '.approval_required')
  approval_seq=''
  approval_step_id=acceptance:$id
  if [ "$approval_required" = "true" ]; then
    approval_seq=$(latest_approval_seq "$run_dir" "$approval_step_id" "$cmd" "$effective")
  fi
  if [ "$approval_required" = "true" ] && [ -z "$approval_seq" ]; then
    payload=$run_dir/approval-required-acceptance-$id.json
    printf '%s\n' "$policy" | jq --arg step_id "$approval_step_id" --arg command "$cmd" \
      '. + {step_id: $step_id, command: $command}' >"$payload.tmp"
    mv "$payload.tmp" "$payload"
    "$SCRIPT_DIR/record-event.sh" --run "$run_id" --event HumanApprovalRequired --payload "$payload"
    die "$EX_ARTIFACT" "approval required for acceptance check $id ($effective)"
  fi
  set +e
  evidence=$("$SCRIPT_DIR/collect-evidence.sh" --run "$run_id" --kind acceptance --id "$id" \
    --risk "$risk" --effective-risk "$effective" --approval-seq "$approval_seq" \
    --cwd "$rel_cwd" --command "$cmd")
  actual=$?
  set -e
  # No evidence path on stdout means collect-evidence failed BEFORE running
  # the command: do not confuse its own exit code with the check's result
  # (a check with expected_exit 5 would falsely pass with zero evidence).
  if [ -z "$evidence" ]; then
    if [ "$actual" -eq "$EX_BUDGET" ]; then
      die "$EX_BUDGET" "budget exceeded while collecting evidence for check $id"
    fi
    die "$EX_ARTIFACT" "evidence collection failed for check $id (exit $actual)"
  fi
  payload=$run_dir/acceptance-checked-$id.json
  jq -n --arg check_id "$id" --arg evidence "$evidence" \
    --argjson expected_exit "$expected" --argjson actual_exit "$actual" \
    '{check_id: $check_id, evidence: $evidence,
      expected_exit: $expected_exit, actual_exit: $actual_exit}' >"$payload.tmp"
  mv "$payload.tmp" "$payload"
  "$SCRIPT_DIR/record-event.sh" --run "$run_id" --event AcceptanceChecked --payload "$payload"
  [ "$actual" -eq "$expected" ] || failures=$((failures + 1))
  printf '%s\n' "$failures" >"$run_dir/.validation-failures.tmp"
done

failures=$(cat "$run_dir/.validation-failures.tmp" 2>/dev/null || printf 0)
rm -f "$run_dir/.validation-failures.tmp"
[ "$failures" -eq 0 ] || die "$EX_ARTIFACT" "$failures acceptance check(s) failed"

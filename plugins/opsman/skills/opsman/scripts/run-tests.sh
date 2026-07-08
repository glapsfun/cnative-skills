#!/bin/sh
# Runs acceptance checks through the evidence collector.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"

usage() {
  printf 'usage: run-tests.sh --run <run-id>\n' >&2
}

run_id=''
while [ $# -gt 0 ]; do
  case $1 in
    --run)
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
[ -f "$run_dir/acceptance.yaml" ] || die "$EX_ARTIFACT" "acceptance.yaml missing"
jq -e '.checks | type == "array" and length > 0' "$run_dir/acceptance.yaml" >/dev/null \
  || die "$EX_ARTIFACT" "acceptance.yaml must contain checks[]"

failures=0
jq -c '.checks[]' "$run_dir/acceptance.yaml" | while IFS= read -r check; do
  id=$(printf '%s\n' "$check" | jq -r '.id')
  cmd=$(printf '%s\n' "$check" | jq -r '.command')
  expected=$(printf '%s\n' "$check" | jq -r '.expected_exit')
  set +e
  evidence=$("$SCRIPT_DIR/collect-evidence.sh" --run "$run_id" --kind acceptance --id "$id" \
    --risk R0 --cwd . --command "$cmd")
  actual=$?
  set -e
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

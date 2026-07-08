#!/bin/sh
# Consistency check for a run directory. Reports every problem, exit 5 on any.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/json.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/state.sh"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  printf 'usage: validate-artifacts.sh <run-dir>\n'
  exit 0
fi
if [ $# -ne 1 ]; then
  printf 'usage: validate-artifacts.sh <run-dir>\n' >&2
  exit "$EX_USAGE"
fi

need_cmd jq
run_dir=$1
schemas_dir=$SCRIPT_DIR/../schemas
fail=0

problem() {
  log_error "$1"
  fail=1
}

for f in state.json STATE.md events.jsonl handoff.md; do
  [ -f "$run_dir/$f" ] || problem "missing required file: $f"
done
[ "$fail" -eq 0 ] || exit "$EX_ARTIFACT"

if ! json_valid "$run_dir/state.json"; then
  problem "state.json is not valid JSON"
elif ! schema_check "$schemas_dir/state.schema.json" "$run_dir/state.json"; then
  problem "state.json is missing required keys"
fi

n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  printf '%s\n' "$line" | jq -e . >/dev/null 2>&1 \
    || problem "events.jsonl line $n: invalid JSON"
done <"$run_dir/events.jsonl"
[ "$n" -gt 0 ] || problem "events.jsonl is empty"

if [ "$fail" -eq 0 ]; then
  status=$(current_status "$run_dir")
  state_seq=$(jq -r '.seq' "$run_dir/state.json")
  jq -es \
    --arg status "$status" \
    --argjson state_seq "$state_seq" '
      . as $ev
      | (reduce range(length) as $i (true; . and ($ev[$i].seq == $i + 1)))
        and (reduce range(length) as $i (true;
          . and ($ev[$i] | has("seq") and has("ts") and has("event") and has("to"))))
        and ($ev[length - 1].to == $status)
        and (length == $state_seq)
    ' "$run_dir/events.jsonl" >/dev/null 2>&1 \
    || problem "event log inconsistent with state.json (seq chain, keys, or status)"
fi

[ "$fail" -eq 0 ] || exit "$EX_ARTIFACT"
log_info "artifacts valid: $run_dir"

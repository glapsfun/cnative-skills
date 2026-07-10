#!/bin/sh
# Reattaches a run: repair the journal tail, rebuild state from the journal,
# validate artifacts, repoint .opsman/current, print the handoff and the
# current role packet — all inside one lock cycle, so exit 0 means resumed.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/state.sh"

usage() {
  printf 'usage: resume.sh [<run-id>]\n' >&2
}

# Help is honored only as the leading argument; any flag after a run-id is a
# usage error (exit 2), so exit 0 can never mean "printed usage, resumed
# nothing" to a caller.
case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
esac

run_id=''
while [ $# -gt 0 ]; do
  case $1 in
    -*)
      usage
      exit "$EX_USAGE"
      ;;
    *)
      if [ -n "$run_id" ]; then
        usage
        exit "$EX_USAGE"
      fi
      run_id=$1
      shift
      ;;
  esac
done

need_cmd jq

list_runs() {
  if [ -d "$OPSMAN_RUNS_DIR" ] && [ -n "$(ls -A "$OPSMAN_RUNS_DIR" 2>/dev/null)" ]; then
    printf 'opsman: known runs:\n' >&2
    # shellcheck disable=SC2012  # run ids are kernel-generated (ops-<ts>-<hex>)
    ls -1 "$OPSMAN_RUNS_DIR" | sed 's/^/opsman:   /' >&2
  fi
}

if [ -z "$run_id" ]; then
  if [ ! -f "$OPSMAN_CURRENT_FILE" ]; then
    list_runs
    die "$EX_USAGE" "no active run pointer; pick one: opsman resume <run-id>"
  fi
  run_id=$(cat "$OPSMAN_CURRENT_FILE")
fi
run_dir=$OPSMAN_RUNS_DIR/$run_id
if [ ! -f "$run_dir/state.json" ]; then
  list_runs
  die "$EX_USAGE" "no such run: $run_id"
fi
[ -f "$run_dir/events.jsonl" ] || die "$EX_ARTIFACT" "run $run_id has no events.jsonl"

"$SCRIPT_DIR/acquire-lock.sh"
trap '"$SCRIPT_DIR/release-lock.sh"' EXIT

# Journal-tail repair. A crash mid-append leaves the file without a trailing
# newline — either a complete event missing only its terminator (repair by
# terminating it, so wc -l counts it and the sync below sees it) or a torn
# fragment (quarantine to events.jsonl.rej).
if [ -s "$run_dir/events.jsonl" ] && [ -n "$(tail -c 1 "$run_dir/events.jsonl")" ]; then
  last=$(tail -n 1 "$run_dir/events.jsonl")
  if printf '%s\n' "$last" | jq -e . >/dev/null 2>&1; then
    printf '\n' >>"$run_dir/events.jsonl"
    log_warn "terminated an unterminated final journal event (run $run_id)"
  else
    # Truncate first, then archive: a crash between the two steps must not
    # leave the torn line in the journal for a second (duplicating) pass.
    awk 'NR > 1 { print prev } { prev = $0 }' "$run_dir/events.jsonl" >"$run_dir/events.jsonl.tmp"
    mv "$run_dir/events.jsonl.tmp" "$run_dir/events.jsonl"
    printf '%s\n' "$last" >>"$run_dir/events.jsonl.rej"
    log_warn "quarantined torn journal tail to events.jsonl.rej (run $run_id)"
    [ -s "$run_dir/events.jsonl" ] \
      || die "$EX_ARTIFACT" "run $run_id has no intact journal events left after quarantine; it cannot be resumed"
  fi
fi

# The journal wins; state.json and the markdown mirrors are derived.
sync_state_with_log "$run_dir"
write_state_md "$run_dir"
write_handoff_md "$run_dir" "$SCRIPT_DIR/state-machine.tsv"

"$SCRIPT_DIR/validate-artifacts.sh" "$run_dir"

# Repoint only after the run verified: a failed resume never moves the pointer.
printf '%s\n' "$run_id" >"$OPSMAN_CURRENT_FILE.tmp"
mv "$OPSMAN_CURRENT_FILE.tmp" "$OPSMAN_CURRENT_FILE"

cat "$run_dir/handoff.md"
status=$(current_status "$run_dir")
if is_terminal_state "$status"; then
  printf '\nRun %s is %s. Result: %s\n' "$run_id" "$status" "$run_dir/result.md"
elif [ "$status" = "BLOCKED" ]; then
  printf '\nRun %s is BLOCKED. Result so far: %s\nLegal ways out are listed above (escalate for approval or abandon).\n' \
    "$run_id" "$run_dir/result.md"
elif [ "$status" = "WAITING_APPROVAL" ]; then
  return_to=$(jq -r '.approval.return_to // "unknown"' "$run_dir/state.json")
  kind='command'
  if [ "$return_to" = "JUDGING" ]; then
    kind=continuation
  fi
  printf '\nPending approval (kind: %s, returns to %s). Record it with:\n  opsman record --event ApprovalGranted --payload <approval.json>\n' \
    "$kind" "$return_to"
elif [ -n "$(role_for_state "$SCRIPT_DIR/roles.tsv" "$status")" ]; then
  # Active role states also get the current packet, rendered under the same
  # lock the repair ran in — no window for another process to shift state.
  render_packet_for_current_state "$SCRIPT_DIR" "$run_id" "$run_dir"
fi

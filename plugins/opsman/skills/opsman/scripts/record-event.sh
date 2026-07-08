#!/bin/sh
# The only state mutator: validates, transitions, appends, rewrites — locked.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/json.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/state.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/gates.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/budget.sh"

usage() {
  printf 'usage: record-event.sh --run <run-id> --event <Event> [--payload <file.json>]\n' >&2
}

run_id=''
event=''
payload=''
while [ $# -gt 0 ]; do
  case $1 in
    --run)
      run_id=$2
      shift 2
      ;;
    --event)
      event=$2
      shift 2
      ;;
    --payload)
      payload=$2
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
if [ -z "$run_id" ] || [ -z "$event" ]; then
  usage
  exit "$EX_USAGE"
fi

need_cmd jq
run_dir=$OPSMAN_RUNS_DIR/$run_id
[ -f "$run_dir/state.json" ] || die "$EX_ARTIFACT" "no such run: $run_id"

table=$SCRIPT_DIR/state-machine.tsv
schemas_dir=$SCRIPT_DIR/../schemas

payload_json='{}'
if [ -n "$payload" ]; then
  json_valid "$payload" || die "$EX_ARTIFACT" "payload is not valid JSON: $payload"
  payload_json=$(jq -c . "$payload")
fi

"$SCRIPT_DIR/acquire-lock.sh"
trap '"$SCRIPT_DIR/release-lock.sh"' EXIT

schema_check "$schemas_dir/state.schema.json" "$run_dir/state.json" \
  || die "$EX_ARTIFACT" "state.json failed schema check: $run_dir/state.json"

# Self-heal a crash between event append and state rewrite: the event log is
# the source of truth, so rebuild status/seq/approval from it when it is ahead.
sync_state_with_log "$run_dir"

cur=$(current_status "$run_dir")
nxt=$("$SCRIPT_DIR/transition.sh" --table "$table" "$cur" "$event")

approval_mode=keep
if [ "$nxt" = "@return" ]; then
  nxt=$(jq -r '.approval.return_to // empty' "$run_dir/state.json")
  [ -n "$nxt" ] || die "$EX_STATE" "$event with no recorded approval.return_to state"
  approval_mode=clear
elif [ "$nxt" = "WAITING_APPROVAL" ] && [ "$cur" != "WAITING_APPROVAL" ]; then
  # Keyed on the destination state, not the event name, so every route into
  # WAITING_APPROVAL records where to return — and re-entries never clobber it.
  approval_mode='set'
fi

check_budget "$event" "$run_dir" "$cur" "$nxt" "$payload"

enforce_exit_gate "$event" "$run_dir" "$schemas_dir" "$SCRIPT_DIR" "$payload"

seq=$(jq -r '.seq' "$run_dir/state.json")
new_seq=$((seq + 1))

jq -cn \
  --argjson seq "$new_seq" \
  --arg ts "$(utc_now)" \
  --arg event "$event" \
  --arg from "$cur" \
  --arg to "$nxt" \
  --argjson payload "$payload_json" \
  '{seq: $seq, ts: $ts, event: $event, from: $from, to: $to, payload: $payload}' \
  >>"$run_dir/events.jsonl"

jq --arg to "$nxt" --arg event "$event" --argjson payload "$payload_json" \
  --argjson seq "$new_seq" --arg mode "$approval_mode" --arg rt "$cur" \
  '.status = $to | .seq = $seq
   | (if $mode == "set" then .approval = {return_to: $rt}
      elif $mode == "clear" then .approval = null
      else . end)
   | (if $event == "WorktreePrepared" then
        .worktree = {path: $payload.path, base_revision: $payload.base_revision}
      else . end)' \
  "$run_dir/state.json" >"$run_dir/state.json.tmp"
mv "$run_dir/state.json.tmp" "$run_dir/state.json"

write_state_md "$run_dir"
write_handoff_md "$run_dir" "$table"

# Terminal states get their derived artifacts mechanically. A finalize
# failure must not fail the transition: the event log is truth, result.md
# is derived and regenerable by rerunning finalize.sh.
case $nxt in
  COMPLETED | BLOCKED | ABANDONED)
    "$SCRIPT_DIR/finalize.sh" "$run_dir" \
      || log_warn "finalize failed for $run_id — rerun: finalize.sh $run_dir"
    ;;
esac

log_info "$run_id: $cur + $event -> $nxt (seq $new_seq)"

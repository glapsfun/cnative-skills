#!/bin/sh
# Initializes a new opsman run in the target repository's .opsman/ dir.
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
  printf 'usage: init-run.sh "<task description>"\n' >&2
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "")
    usage
    exit "$EX_USAGE"
    ;;
esac

need_cmd jq
need_cmd git

task=$1
ts=$(date -u '+%Y%m%d-%H%M%S')
rand=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')
run_id="ops-$ts-$rand"
run_dir=$OPSMAN_RUNS_DIR/$run_id

mkdir -p "$run_dir/attempts" "$run_dir/evidence" "$run_dir/tests" \
  "$run_dir/reviews" "$run_dir/oracle" "$run_dir/context"

revision=$(git -C "$OPSMAN_ROOT" rev-parse HEAD 2>/dev/null || printf 'none')
dirty=false
if [ -n "$(git -C "$OPSMAN_ROOT" status --porcelain 2>/dev/null)" ]; then
  dirty=true
fi

jq -n \
  --arg run_id "$run_id" \
  --arg task "$task" \
  --arg root "$OPSMAN_ROOT" \
  --arg revision "$revision" \
  --argjson dirty "$dirty" \
  '{
    schema_version: "1.0",
    run_id: $run_id,
    status: "DISCOVERING",
    seq: 1,
    task: { raw_input: $task, domain: null, risk: null, acceptance_criteria: [] },
    repository: { root: $root, revision: $revision, dirty: $dirty },
    approval: null
  }' >"$run_dir/state.json.tmp"
mv "$run_dir/state.json.tmp" "$run_dir/state.json"

jq -cn --arg ts "$(utc_now)" --arg task "$task" \
  '{seq: 1, ts: $ts, event: "RunStarted", from: null, to: "DISCOVERING", payload: {task: $task}}' \
  >>"$run_dir/events.jsonl"

printf '%s\n' "$run_id" >"$OPSMAN_CURRENT_FILE.tmp"
mv "$OPSMAN_CURRENT_FILE.tmp" "$OPSMAN_CURRENT_FILE"

# Keep run state out of the target repo's history.
gitignore=$OPSMAN_ROOT/.gitignore
if ! grep -qx '\.opsman/' "$gitignore" 2>/dev/null; then
  printf '.opsman/\n' >>"$gitignore"
fi

write_state_md "$run_dir"
write_handoff_md "$run_dir" "$SCRIPT_DIR/state-machine.tsv"

log_info "run $run_id initialized (state: DISCOVERING)"
printf '%s\n' "$run_id"

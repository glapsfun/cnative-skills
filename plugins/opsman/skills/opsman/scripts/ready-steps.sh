#!/bin/sh
# Lists the DAG-ready, parallel-eligible plan steps for the current batch:
# deps satisfied, not yet completed, command-backed, allowed_files declared,
# declared risk R0-R2. Capped at limits.json's max_parallel_steps (default
# 4). Read-only — no state mutation, no lock.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/budget.sh"

usage() {
  printf 'usage: ready-steps.sh --run <run-id>\n' >&2
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
status=$(jq -r '.status' "$run_dir/state.json")
[ "$status" = "IMPLEMENTING" ] \
  || die "$EX_STATE" "run $run_id is in $status; ready-steps requires IMPLEMENTING"
[ -f "$run_dir/plan.yaml" ] || die "$EX_ARTIFACT" "plan.yaml missing"

max=$(_limit "$run_dir" max_parallel_steps 4)
completed_ids=$(jq -cs '[.[] | select(.event == "StepCompleted") | .payload.step_id] | unique' \
  "$run_dir/events.jsonl")

# A step with a scratch worktree still on disk is either genuinely in
# flight (step-run.sh running or awaiting step-land.sh) or failed and left
# for diagnosis (see step-run.sh) — either way it must not be re-offered
# here, or a misbehaving caller re-invoking ready-steps mid-batch could
# dispatch the same step id twice and race step-run.sh's create_step_worktree
# on the identical scratch path.
step_wt_dir=$OPSMAN_STEP_WORKTREES_DIR/$run_id
if [ -d "$step_wt_dir" ]; then
  inflight_ids=$(find "$step_wt_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
    | jq -R -s 'split("\n") | map(select(length > 0))')
else
  inflight_ids='[]'
fi

jq --argjson completed "$completed_ids" --argjson inflight "$inflight_ids" --argjson max "$max" '
  .steps
  | map(select(
      ((.id as $id | ($completed | index($id))) == null)
      and ((.id as $id | ($inflight | index($id))) == null)
      and ((.depends_on - $completed) | length == 0)
      and ((.command // "") | length > 0)
      and ((.allowed_files // []) | length > 0)
      and (.risk == "R0" or .risk == "R1" or .risk == "R2")
    ))
  | map(.id)
  | .[0:$max]
' "$run_dir/plan.yaml"

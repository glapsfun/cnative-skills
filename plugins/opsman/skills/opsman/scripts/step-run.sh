#!/bin/sh
# Executes one command-backed plan step in an isolated scratch copy of the
# live worktree. No state mutation — safe to call concurrently for
# different step ids. The orchestrator lands a successful result with
# `opsman step-land`; an approval-required result is handled by the
# orchestrator recording HumanApprovalRequired directly, after landing the
# rest of the current batch.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/evidence.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/scope.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/parallel.sh"

usage() {
  printf 'usage: step-run.sh --run <run-id> <step-id>\n' >&2
}

run_id=''
step_id=''
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
      [ -z "$step_id" ] || {
        usage
        exit "$EX_USAGE"
      }
      step_id=$1
      shift
      ;;
  esac
done
if [ -z "$run_id" ] || [ -z "$step_id" ]; then
  usage
  exit "$EX_USAGE"
fi

need_cmd jq
need_cmd git
run_dir=$OPSMAN_RUNS_DIR/$run_id
[ -f "$run_dir/state.json" ] || die "$EX_ARTIFACT" "no such run: $run_id"
status=$(jq -r '.status' "$run_dir/state.json")
[ "$status" = "IMPLEMENTING" ] \
  || die "$EX_STATE" "run $run_id is in $status; step-run requires IMPLEMENTING"
[ -f "$run_dir/plan.yaml" ] || die "$EX_ARTIFACT" "plan.yaml missing"
jq -e --arg id "$step_id" '.steps[] | select(.id == $id)' "$run_dir/plan.yaml" >/dev/null \
  || die "$EX_ARTIFACT" "unknown plan step: $step_id"

step_json=$(jq -c --arg id "$step_id" '.steps[] | select(.id == $id)' "$run_dir/plan.yaml")
cmd=$(printf '%s\n' "$step_json" | jq -r '.command // empty')
[ -n "$cmd" ] \
  || die "$EX_USAGE" "step '$step_id' has no command; step-run only handles command-backed steps"

missing=$(jq -r --arg id "$step_id" --slurpfile ev "$run_dir/events.jsonl" '
  (.steps[] | select(.id == $id) | .depends_on[]) as $dep
  | select(any($ev[]; .event == "StepCompleted" and .payload.step_id == $dep) | not)
  | $dep' "$run_dir/plan.yaml" | head -n 1)
[ -z "$missing" ] || die "$EX_ARTIFACT" "dependency not complete for $step_id: $missing"

wt=$(jq -r '.worktree.path // empty' "$run_dir/state.json")
[ -n "$wt" ] && [ -d "$wt" ] || die "$EX_ARTIFACT" "worktree missing; run: opsman worktree"

risk=$(printf '%s\n' "$step_json" | jq -r '.risk')
rel_cwd=$(printf '%s\n' "$step_json" | jq -r '.cwd // "."')
policy=$("$SCRIPT_DIR/policy-check.sh" --risk "$risk" --command "$cmd")
effective=$(printf '%s\n' "$policy" | jq -r '.effective_risk')
approval_required=$(printf '%s\n' "$policy" | jq -r '.approval_required')
approval_seq=''
if [ "$approval_required" = "true" ]; then
  approval_seq=$(latest_approval_seq "$run_dir" "$step_id" "$cmd" "$effective")
fi
if [ "$approval_required" = "true" ] && [ -z "$approval_seq" ]; then
  payload=$run_dir/approval-required-$step_id.json
  printf '%s\n' "$policy" | jq --arg step_id "$step_id" --arg command "$cmd" \
    '. + {step_id: $step_id, command: $command}' >"$payload.tmp"
  mv "$payload.tmp" "$payload"
  die "$EX_ARTIFACT" "approval required for step $step_id ($effective); land the rest of the batch, then: opsman record --event HumanApprovalRequired --payload $payload"
fi

base=$(git -C "$wt" rev-parse HEAD)
mkdir -p "$OPSMAN_STEP_WORKTREES_DIR"
scratch=$(create_step_worktree "$run_id" "$step_id" "$base") \
  || die "$EX_ARTIFACT" "could not create scratch worktree for step $step_id"
overlay_worktree "$wt" "$scratch" \
  || die "$EX_ARTIFACT" "could not sync scratch worktree for step $step_id"

parallel_dir=$run_dir/parallel/$step_id
mkdir -p "$parallel_dir"
baseline_snapshot "$scratch" "$parallel_dir/pre.tsv"

set +e
evidence=$("$SCRIPT_DIR/collect-evidence.sh" --run "$run_id" --kind step --id "$step_id" \
  --worktree "$scratch" --risk "$risk" --effective-risk "$effective" \
  --approval-seq "$approval_seq" --cwd "$rel_cwd" --command "$cmd")
code=$?
set -e

baseline_snapshot "$scratch" "$parallel_dir/post.tsv"

if [ -z "$evidence" ]; then
  if [ "$code" -eq "$EX_BUDGET" ]; then
    die "$EX_BUDGET" "budget exceeded while collecting evidence for step $step_id"
  fi
  die "$EX_ARTIFACT" "evidence collection failed for step $step_id (exit $code)"
fi
[ "$code" -eq 0 ] || die "$EX_ARTIFACT" "step $step_id failed with exit $code; evidence: $evidence"

printf '%s\n' "$evidence"

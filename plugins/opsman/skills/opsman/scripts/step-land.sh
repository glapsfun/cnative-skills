#!/bin/sh
# Merges one step-run.sh success into the main worktree and records
# StepCompleted via the unchanged record-event.sh path. Must be invoked one
# at a time per run — concurrent step-land calls for the same run are the
# orchestrator's job to avoid, not this script's.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/scope.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/parallel.sh"

usage() {
  printf 'usage: step-land.sh --run <run-id> --batch <id1,id2,...> --evidence <dir> <step-id>\n' >&2
}

run_id=''
batch=''
evidence=''
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
    --batch)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      batch=$2
      shift 2
      ;;
    --evidence)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      evidence=$2
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
if [ -z "$run_id" ] || [ -z "$batch" ] || [ -z "$evidence" ] || [ -z "$step_id" ]; then
  usage
  exit "$EX_USAGE"
fi

need_cmd jq
need_cmd git
run_dir=$OPSMAN_RUNS_DIR/$run_id
[ -f "$run_dir/state.json" ] || die "$EX_ARTIFACT" "no such run: $run_id"
[ -f "$run_dir/plan.yaml" ] || die "$EX_ARTIFACT" "plan.yaml missing"
jq -e --arg id "$step_id" '.steps[] | select(.id == $id)' "$run_dir/plan.yaml" >/dev/null \
  || die "$EX_ARTIFACT" "unknown plan step: $step_id"
step_json=$(jq -c --arg id "$step_id" '.steps[] | select(.id == $id)' "$run_dir/plan.yaml")
cmd=$(printf '%s\n' "$step_json" | jq -r '.command // empty')

parallel_dir=$run_dir/parallel/$step_id
pre=$parallel_dir/pre.tsv
post=$parallel_dir/post.tsv
[ -f "$pre" ] && [ -f "$post" ] \
  || die "$EX_ARTIFACT" "no step-run snapshots for $step_id; run: opsman step-run $step_id"

delta=$(snapshot_delta "$pre" "$post")
tab=$(printf '\t')

# Scope check: every delta path must match this step's own allowed_files.
patterns=$(printf '%s\n' "$step_json" | jq -r '.allowed_files[]?')
if [ -n "$patterns" ] && [ -n "$delta" ]; then
  stray=$(printf '%s\n' "$delta" | while IFS="$tab" read -r _h p; do
    [ -n "$p" ] || continue
    _scope_match "$p" "$patterns" || printf '%s\n' "$p"
  done)
  [ -z "$stray" ] || die "$EX_ARTIFACT" \
    "step $step_id delta strays outside allowed_files: $(printf '%s' "$stray" | tr '\n' ' ')"
fi

delta_paths=$(printf '%s\n' "$delta" | cut -f2)

# Batch-sibling collision check: only against already-landed members of the
# SAME batch. A later, unrelated sequential step touching the same path is
# normal depends_on-chain behavior and must never be flagged here.
tmp_delta=$(mktemp)
printf '%s\n' "$delta_paths" | LC_ALL=C sort -u >"$tmp_delta"
old_ifs=$IFS
IFS=,
for other in $batch; do
  IFS=$old_ifs
  [ -n "$other" ] && [ "$other" != "$step_id" ] || continue
  landed=$run_dir/parallel/$other/landed-paths.txt
  [ -f "$landed" ] || continue
  # landed-paths.txt is written pre-sorted (see below), so this can compare
  # against it directly instead of re-sorting it into a fresh temp file on
  # every batch sibling's land call.
  collision=$(comm -12 "$tmp_delta" "$landed")
  if [ -n "$collision" ]; then
    rm -f "$tmp_delta"
    die "$EX_ARTIFACT" \
      "step $step_id collides with already-landed $other on: $(printf '%s' "$collision" | tr '\n' ' ')"
  fi
done
IFS=$old_ifs
rm -f "$tmp_delta"

wt=$(jq -r '.worktree.path // empty' "$run_dir/state.json")
[ -n "$wt" ] && [ -d "$wt" ] || die "$EX_ARTIFACT" "worktree missing; run: opsman worktree"
scratch=$OPSMAN_STEP_WORKTREES_DIR/$run_id/$step_id
[ -d "$scratch" ] || die "$EX_ARTIFACT" "scratch worktree missing for $step_id: $scratch"

if [ -n "$delta" ]; then
  printf '%s\n' "$delta" | while IFS="$tab" read -r hash path; do
    [ -n "$path" ] || continue
    if [ "$hash" = "missing" ]; then
      rm -f "$wt/$path"
    else
      mkdir -p "$(dirname -- "$wt/$path")"
      cp "$scratch/$path" "$wt/$path"
    fi
  done
fi

# Final belt-and-suspenders: full-plan scope check on the main worktree.
bl=$run_dir/baseline-dirty.tsv
[ -f "$bl" ] || bl=''
final_viol=$(scope_violations "$wt" "$run_dir/plan.yaml" "$bl") \
  || die "$EX_ARTIFACT" "scope check failed for step $step_id: worktree unreadable: $wt"
[ -z "$final_viol" ] || die "$EX_ARTIFACT" \
  "step $step_id landed but violates plan allowed_files scope: $(printf '%s' "$final_viol" | tr '\n' ' ')"

# Written before record-event.sh on purpose: the delta is already physically
# copied into $wt above, so a sibling's collision check must see these paths
# as claimed even if the StepCompleted recording below fails (lock
# contention, a gate mismatch) — the alternative order would let a sibling
# land onto a path this step already dirtied. A dangling landed-paths.txt
# with no matching StepCompleted event is a sign to inspect $wt by hand.
printf '%s\n' "$delta_paths" | LC_ALL=C sort -u >"$parallel_dir/landed-paths.txt"

payload=$run_dir/step-completed-$step_id.json
jq -n --arg step_id "$step_id" --arg evidence "$evidence" --arg command "$cmd" \
  '{step_id: $step_id, evidence: $evidence, command: $command}' >"$payload.tmp"
mv "$payload.tmp" "$payload"
"$SCRIPT_DIR/record-event.sh" --run "$run_id" --event StepCompleted --payload "$payload"

remove_step_worktree "$run_id" "$step_id"
printf '%s\n' "$evidence"

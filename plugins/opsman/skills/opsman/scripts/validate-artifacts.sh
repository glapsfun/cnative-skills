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
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/gates.sh"

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
table=$SCRIPT_DIR/state-machine.tsv
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

# Replay the log against the transition table: every event must chain from
# the previous one and be legal per state-machine.tsv, or the promised
# "state is rebuildable by replaying events.jsonl" guarantee is void.
if [ "$fail" -eq 0 ]; then
  tab=$(printf '\t')
  prev_to=''
  return_to=''
  i=0
  jq -r '.[] | [(.from // "null"), .event, .to] | @tsv' -s "$run_dir/events.jsonl" \
    | while IFS="$tab" read -r ev_from ev_name ev_to; do
      i=$((i + 1))
      if [ "$i" -eq 1 ]; then
        if [ "$ev_name" != "RunStarted" ] || [ "$ev_from" != "null" ] || [ "$ev_to" != "DISCOVERING" ]; then
          printf 'bad-first-event\n'
        fi
      else
        [ "$ev_from" = "$prev_to" ] || printf 'broken-chain@%s\n' "$i"
        expected=$(next_state "$table" "$ev_from" "$ev_name")
        [ "$expected" = "@return" ] && expected=$return_to
        if [ -z "$expected" ] || [ "$expected" != "$ev_to" ]; then
          printf 'illegal-transition@%s\n' "$i"
        fi
      fi
      if [ "$ev_to" = "WAITING_APPROVAL" ] && [ "$ev_from" != "WAITING_APPROVAL" ]; then
        return_to=$ev_from
      elif [ "$ev_from" = "WAITING_APPROVAL" ] && [ "$ev_to" != "WAITING_APPROVAL" ]; then
        return_to=''
      fi
      prev_to=$ev_to
    done >"$run_dir/.replay-problems.tmp"
  if [ -s "$run_dir/.replay-problems.tmp" ]; then
    problem "event log fails transition replay: $(tr '\n' ' ' <"$run_dir/.replay-problems.tmp")"
  fi
  rm -f "$run_dir/.replay-problems.tmp"
fi

# Gated artifacts must survive past their gate: if the log shows a phase-exit
# event, its artifact must still exist and parse (deep rules live in the
# gates; this guards post-hoc deletion or corruption).
if [ "$fail" -eq 0 ]; then
  has_event() {
    jq -es --arg e "$1" 'any(.[]; .event == $e)' "$run_dir/events.jsonl" >/dev/null 2>&1
  }
  if has_event TaskClassified; then
    { json_valid "$run_dir/problem.yaml" \
      && schema_check "$schemas_dir/problem.schema.json" "$run_dir/problem.yaml"; } 2>/dev/null \
      || problem "problem.yaml missing or invalid despite TaskClassified"
  fi
  if has_event SkillsSelected; then
    { json_valid "$run_dir/selected-skills.yaml" \
      && schema_check "$schemas_dir/selected-skills.schema.json" "$run_dir/selected-skills.yaml"; } 2>/dev/null \
      || problem "selected-skills.yaml missing or invalid despite SkillsSelected"
  fi
  if has_event PlanCreated; then
    "$SCRIPT_DIR/check-plan.sh" "$run_dir/plan.yaml" >/dev/null 2>&1 \
      || problem "plan.yaml missing or invalid despite PlanCreated"
  fi
  if has_event BaselineRecorded; then
    { _acceptance_ok "$run_dir" "$schemas_dir" || _waiver_ok "$run_dir"; } \
      || problem "acceptance.yaml (or a current TDD waiver) missing/invalid despite BaselineRecorded"
  fi
  if has_event WorktreePrepared; then
    jq -es 'all([.[] | select(.event == "WorktreePrepared")][];
      ((.payload.path // "") | length > 0) and ((.payload.base_revision // "") | length > 0))' \
      "$run_dir/events.jsonl" >/dev/null 2>&1 \
      || problem "WorktreePrepared event missing path/base_revision"
  fi
  if has_event StepCompleted; then
    jq -es 'all([.[] | select(.event == "StepCompleted")][];
      ((.payload.step_id // "") | length > 0) and ((.payload.evidence // "") | length > 0))' \
      "$run_dir/events.jsonl" >/dev/null 2>&1 \
      || problem "StepCompleted event missing step_id/evidence"
  fi
  if has_event AcceptanceChecked; then
    jq -es 'all([.[] | select(.event == "AcceptanceChecked")][];
      ((.payload.check_id // "") | length > 0)
      and ((.payload.evidence // "") | length > 0)
      and (.payload.actual_exit | type == "number")
      and (.payload.expected_exit | type == "number"))' \
      "$run_dir/events.jsonl" >/dev/null 2>&1 \
      || problem "AcceptanceChecked event missing check_id/evidence/exit fields"
  fi
fi

[ "$fail" -eq 0 ] || exit "$EX_ARTIFACT"
log_info "artifacts valid: $run_dir"

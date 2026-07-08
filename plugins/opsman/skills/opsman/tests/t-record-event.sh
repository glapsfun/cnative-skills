#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

# fixture skill + registry so the M2 exit gates can be satisfied
mkdir -p "$repo/.claude/skills/probe"
printf -- '---\nname: probe\ndescription: probe task fixture skill\n---\n' \
  >"$repo/.claude/skills/probe/SKILL.md"
"$SCRIPTS_DIR/build-registry.sh"

run_id=$("$SCRIPTS_DIR/init-run.sh" "task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
R=$SCRIPTS_DIR/record-event.sh

# usage errors
assert_status 2 "$R"
assert_status 2 "$R" --run "$run_id"

# unknown run
assert_status 5 "$R" --run nope --event SkillsIndexed

# legal transition advances state and seq, appends event
"$R" --run "$run_id" --event SkillsIndexed
assert_eq "$(jq -r '.status' "$rd/state.json")" UNDERSTANDING
assert_eq "$(jq -r '.seq' "$rd/state.json")" 2
assert_eq "$(wc -l <"$rd/events.jsonl" | tr -d ' ')" 2
assert_eq "$(tail -n 1 "$rd/events.jsonl" | jq -r '.from')" DISCOVERING
assert_eq "$(tail -n 1 "$rd/events.jsonl" | jq -r '.to')" UNDERSTANDING

# STATE.md and handoff.md were regenerated
grep -q 'UNDERSTANDING' "$rd/STATE.md" || fail "STATE.md not regenerated"
grep -q 'TaskClassified' "$rd/handoff.md" || fail "handoff.md not regenerated"

# illegal transition: exit 3, state unchanged, no event appended, lock released
assert_status 3 "$R" --run "$run_id" --event OracleApproved
assert_eq "$(jq -r '.status' "$rd/state.json")" UNDERSTANDING
assert_eq "$(wc -l <"$rd/events.jsonl" | tr -d ' ')" 2
[ ! -d "$repo/.opsman/lock" ] || fail "lock leaked after failure"

# payload round-trip (satisfy the TaskClassified gate first)
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["task"]' "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
printf '{"domain":"ops"}\n' >"$sandbox/p.json"
"$R" --run "$run_id" --event TaskClassified --payload "$sandbox/p.json"
assert_eq "$(tail -n 1 "$rd/events.jsonl" | jq -r '.payload.domain')" ops

# invalid payload: exit 5, nothing recorded
printf 'not json\n' >"$sandbox/bad.json"
assert_status 5 "$R" --run "$run_id" --event SkillsSelected --payload "$sandbox/bad.json"
assert_eq "$(jq -r '.status' "$rd/state.json")" SELECTING

# approval round-trip: return_to is saved and honored
"$R" --run "$run_id" --event HumanApprovalRequired
assert_eq "$(jq -r '.status' "$rd/state.json")" WAITING_APPROVAL
assert_eq "$(jq -r '.approval.return_to' "$rd/state.json")" SELECTING
"$R" --run "$run_id" --event ApprovalGranted
assert_eq "$(jq -r '.status' "$rd/state.json")" SELECTING
assert_eq "$(jq -r '.approval' "$rd/state.json")" null

# held lock: exit 4
"$SCRIPTS_DIR/acquire-lock.sh"
assert_status 4 "$R" --run "$run_id" --event SkillsSelected
"$SCRIPTS_DIR/release-lock.sh"

# approval is destination-keyed: OracleNeedsHuman must also record return_to
# (satisfy the M2 gates along the way)
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "probe", role: "primary", reason: "test fixture"}]}' \
  >"$rd/selected-skills.yaml"
"$R" --run "$run_id" --event SkillsSelected
jq -n '{steps: [{id: "s", uses: "probe", depends_on: [], risk: "R0", success: "ok"}]}' \
  >"$rd/plan.yaml"
"$R" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "c", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$R" --run "$run_id" --event BaselineRecorded
"$R" --run "$run_id" --event ImplementationCompleted
"$R" --run "$run_id" --event ValidationCompleted
assert_eq "$(jq -r '.status' "$rd/state.json")" JUDGING
"$R" --run "$run_id" --event OracleNeedsHuman
assert_eq "$(jq -r '.status' "$rd/state.json")" WAITING_APPROVAL
assert_eq "$(jq -r '.approval.return_to' "$rd/state.json")" JUDGING

# a duplicate approval request must not clobber return_to
"$R" --run "$run_id" --event HumanApprovalRequired
assert_eq "$(jq -r '.approval.return_to' "$rd/state.json")" JUDGING
"$R" --run "$run_id" --event ApprovalGranted
assert_eq "$(jq -r '.status' "$rd/state.json")" JUDGING

# terminal states accept no further events
"$R" --run "$run_id" --event OracleApproved
assert_eq "$(jq -r '.status' "$rd/state.json")" COMPLETED
assert_status 3 "$R" --run "$run_id" --event RunAbandoned
assert_eq "$(jq -r '.status' "$rd/state.json")" COMPLETED

# crash recovery: an event appended without a state.json update self-heals
run2=$("$SCRIPTS_DIR/init-run.sh" "task2" | tail -n 1)
rd2=$repo/.opsman/runs/$run2
ev=$(jq -cn --arg ts 2026-01-01T00:00:00Z \
  '{seq: 2, ts: $ts, event: "SkillsIndexed", from: "DISCOVERING", to: "UNDERSTANDING", payload: {}}')
printf '%s\n' "$ev" >>"$rd2/events.jsonl"
"$SCRIPTS_DIR/classify.sh" --run "$run2"
jq '.keywords = ["task2"]' "$rd2/problem.yaml" >"$rd2/problem.yaml.tmp"
mv "$rd2/problem.yaml.tmp" "$rd2/problem.yaml"
"$R" --run "$run2" --event TaskClassified
assert_eq "$(jq -r '.status' "$rd2/state.json")" SELECTING
assert_eq "$(jq -r '.seq' "$rd2/state.json")" 3
"$SCRIPTS_DIR/validate-artifacts.sh" "$rd2"

#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
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

# payload round-trip
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

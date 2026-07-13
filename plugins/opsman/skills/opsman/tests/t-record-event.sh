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

run_id=$("$SCRIPTS_DIR/init-run.sh" --no-q "task" | tail -n 1)
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
jq '.keywords = ["task"] | .domain = "ops"' "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
printf '{"domain":"ops"}\n' >"$sandbox/p.json"
answer_questions_auto "$rd" "$run_id"
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
assert_status 5 "$R" --run "$run_id" --event ApprovalGranted
# a continuation is refused outside an OracleNeedsHuman wait (return_to SELECTING)
printf '{"kind":"continuation","approver":"tester","approved_at":"2026-01-01T00:00:00Z","note":"continue"}\n' \
  >"$sandbox/approval-cont-bad.json"
assert_status 5 "$R" --run "$run_id" --event ApprovalGranted --payload "$sandbox/approval-cont-bad.json"
printf '{"kind":"command","step_id":"select-approval","command":"approve skill selection","effective_risk":"R3","approver":"tester","approved_at":"2026-01-01T00:00:00Z"}\n' \
  >"$sandbox/approval-select.json"
"$R" --run "$run_id" --event ApprovalGranted --payload "$sandbox/approval-select.json"
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
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
printf '{"manual_summary":"record-event fixture implementation"}\n' >"$sandbox/manual-record.json"
"$R" --run "$run_id" --event ImplementationCompleted --payload "$sandbox/manual-record.json"
"$SCRIPTS_DIR/run-tests.sh" --run "$run_id" >/dev/null
"$R" --run "$run_id" --event ValidationCompleted
assert_eq "$(jq -r '.status' "$rd/state.json")" JUDGING
jq -n '{verdict: "needs_human",
  score: {acceptance_criteria: 0, automated_tests: 0, specialist_validation: 0,
          adversarial_review: 0, scope_discipline: 0, safety_compliance: 0, total: 0},
  criteria: [], reason: "record-event fixture: needs a human"}' >"$sandbox/needs-human.json"
"$R" --run "$run_id" --event OracleNeedsHuman --payload "$sandbox/needs-human.json"
assert_eq "$(jq -r '.status' "$rd/state.json")" WAITING_APPROVAL
assert_eq "$(jq -r '.approval.return_to' "$rd/state.json")" JUDGING

# a duplicate approval request must not clobber return_to
"$R" --run "$run_id" --event HumanApprovalRequired
assert_eq "$(jq -r '.approval.return_to' "$rd/state.json")" JUDGING
# a command approval must NOT resolve an OracleNeedsHuman judgment wait
printf '{"kind":"command","step_id":"s9","command":"kubectl delete ns prod","effective_risk":"R4","approver":"tester","approved_at":"2026-01-01T00:00:00Z"}\n' \
  >"$sandbox/approval-cmd-judging.json"
assert_status 5 "$R" --run "$run_id" --event ApprovalGranted --payload "$sandbox/approval-cmd-judging.json"
# the honest shape for an OracleNeedsHuman wait is a continuation
printf '{"kind":"continuation","approver":"tester","approved_at":"2026-01-01T00:00:00Z","note":"approved oracle continuation"}\n' \
  >"$sandbox/approval-oracle.json"
"$R" --run "$run_id" --event ApprovalGranted --payload "$sandbox/approval-oracle.json"
assert_eq "$(jq -r '.status' "$rd/state.json")" JUDGING

# terminal states accept no further events
jq -n '{verdict: "approved",
  score: {acceptance_criteria: 35, automated_tests: 20, specialist_validation: 15,
          adversarial_review: 10, scope_discipline: 10, safety_compliance: 10, total: 100},
  criteria: [], reason: "record-event fixture: all green"}' >"$sandbox/approved.json"
"$R" --run "$run_id" --event OracleApproved --payload "$sandbox/approved.json"
assert_eq "$(jq -r '.status' "$rd/state.json")" COMPLETED
assert_status 3 "$R" --run "$run_id" --event RunAbandoned
assert_eq "$(jq -r '.status' "$rd/state.json")" COMPLETED

# crash recovery: an event appended without a state.json update self-heals
run2=$("$SCRIPTS_DIR/init-run.sh" --no-q "task2" | tail -n 1)
rd2=$repo/.opsman/runs/$run2
ev=$(jq -cn --arg ts 2026-01-01T00:00:00Z \
  '{seq: 2, ts: $ts, event: "SkillsIndexed", from: "DISCOVERING", to: "UNDERSTANDING", payload: {}}')
printf '%s\n' "$ev" >>"$rd2/events.jsonl"
"$SCRIPTS_DIR/classify.sh" --run "$run2"
jq '.keywords = ["task2"] | .domain = "ops"' "$rd2/problem.yaml" >"$rd2/problem.yaml.tmp"
mv "$rd2/problem.yaml.tmp" "$rd2/problem.yaml"
answer_questions_auto "$rd2" "$run2"
"$R" --run "$run2" --event TaskClassified
assert_eq "$(jq -r '.status' "$rd2/state.json")" SELECTING
assert_eq "$(jq -r '.seq' "$rd2/state.json")" 4
"$SCRIPTS_DIR/validate-artifacts.sh" "$rd2"

# replay parity: a continuation approval resolving a non-JUDGING wait must
# fail validate-run just like the live gate would refuse it
jq -cn '{seq: 5, ts: "2026-01-01T00:00:00Z", event: "HumanApprovalRequired",
  from: "SELECTING", to: "WAITING_APPROVAL", payload: {}}' >>"$rd2/events.jsonl"
jq -cn '{seq: 6, ts: "2026-01-01T00:00:01Z", event: "ApprovalGranted",
  from: "WAITING_APPROVAL", to: "SELECTING",
  payload: {kind: "continuation", approver: "tester",
            approved_at: "2026-01-01T00:00:01Z", note: "sneaky"}}' >>"$rd2/events.jsonl"
jq '.seq = 6' "$rd2/state.json" >"$rd2/state.json.tmp"
mv "$rd2/state.json.tmp" "$rd2/state.json"
assert_status 5 "$SCRIPTS_DIR/validate-artifacts.sh" "$rd2"

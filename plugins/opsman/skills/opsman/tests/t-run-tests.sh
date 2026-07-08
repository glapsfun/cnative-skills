#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
T=$SCRIPTS_DIR/run-tests.sh
K=$SCRIPTS_DIR/opsman

mkdir -p "$repo/.claude/skills/foo"
printf -- '---\nname: foo\ndescription: foo execution skill\n---\n' \
  >"$repo/.claude/skills/foo/SKILL.md"
"$SCRIPTS_DIR/build-registry.sh"

run_id=$("$SCRIPTS_DIR/init-run.sh" "validate checks with foo" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["foo"] | .domain = "dev" | .risk = "low"
    | .acceptance_criteria = ["ok"]' "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "foo", role: "primary", reason: "match"}]}' \
  >"$rd/selected-skills.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsSelected
jq -n '{steps: [{id: "s1", uses: "foo", depends_on: [], risk: "R1", success: "ok"}]}' \
  >"$rd/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "boot", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
printf '{"manual_summary":"ready for validation"}\n' >"$sandbox/manual.json"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event ImplementationCompleted --payload "$sandbox/manual.json"

assert_status 2 "$T"
rm "$rd/acceptance.yaml"
assert_status 5 "$T" --run "$run_id"

jq -n '{checks: [
  {id: "pass", command: "true", expected_exit: 0},
  {id: "expected-fail", command: "exit 4", expected_exit: 4}
]}' >"$rd/acceptance.yaml"
"$T" --run "$run_id"
jq -es '[.[] | select(.event == "AcceptanceChecked")] | length == 2' "$rd/events.jsonl" >/dev/null \
  || fail "acceptance events missing"

jq -n '{checks: [
  {id: "bad", command: "exit 3", expected_exit: 0},
  {id: "still-runs", command: "true", expected_exit: 0}
]}' >"$rd/acceptance.yaml"
assert_status 5 "$T" --run "$run_id"
jq -es '[.[] | select(.event == "AcceptanceChecked" and .payload.check_id == "still-runs")] | length >= 1' \
  "$rd/events.jsonl" >/dev/null || fail "runner stopped before later checks"

# Dangerous validation commands follow the same approval flow as plan steps.
jq -n '{checks: [
  {id: "danger", command: "printf validation > validation.txt # kubectl delete", expected_exit: 0}
]}' >"$rd/acceptance.yaml"
assert_status 5 "$T" --run "$run_id"
jq -es '.[length - 1].event == "HumanApprovalRequired" and .[length - 1].to == "WAITING_APPROVAL"' \
  "$rd/events.jsonl" >/dev/null || fail "validation approval event missing"
printf '{"step_id":"acceptance:danger","command":"printf validation > validation.txt # kubectl delete","effective_risk":"R4","approver":"tester","approved_at":"2026-01-01T00:00:00Z"}\n' \
  >"$sandbox/approval-validation.json"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event ApprovalGranted --payload "$sandbox/approval-validation.json"
"$T" --run "$run_id"
jq -es 'any(.[]; .event == "AcceptanceChecked" and .payload.check_id == "danger")' "$rd/events.jsonl" >/dev/null \
  || fail "approved dangerous validation did not record evidence"

"$K" validate >/dev/null || true

# validate refuses to execute outside VALIDATING: no command runs and no
# evidence is written when AcceptanceChecked could not be recorded anyway.
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunBlocked
assert_status 3 "$T" --run "$run_id"

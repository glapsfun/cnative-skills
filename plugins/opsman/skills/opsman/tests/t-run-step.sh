#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
K=$SCRIPTS_DIR/opsman
S=$SCRIPTS_DIR/run-step.sh

mkdir -p "$repo/.claude/skills/foo"
printf -- '---\nname: foo\ndescription: foo execution skill\n---\n' \
  >"$repo/.claude/skills/foo/SKILL.md"
"$SCRIPTS_DIR/build-registry.sh"

run_id=$("$SCRIPTS_DIR/init-run.sh" "execute steps with foo" | tail -n 1)
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
jq -n '{steps: [
  {id: "a", uses: "foo", depends_on: [], risk: "R1", success: "writes file",
   command: "printf done > result.txt", cwd: "."},
  {id: "b", uses: "foo", depends_on: ["a"], risk: "R0", success: "reads file",
   command: "test -f result.txt", cwd: "."},
  {id: "manual", uses: "foo", depends_on: [], risk: "R2", success: "agent edits file"}
]}' >"$rd/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "c", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null

assert_status 2 "$S"
assert_status 5 "$S" --run "$run_id" b
"$S" --run "$run_id" a >/dev/null
jq -es 'any(.[]; .event == "StepCompleted" and .payload.step_id == "a")' "$rd/events.jsonl" >/dev/null \
  || fail "StepCompleted missing"
"$S" --run "$run_id" b >/dev/null
assert_status 2 "$S" --run "$run_id" manual

# Kernel dispatch routes to the current run.
"$K" run-step a >/dev/null

# Policy-required command records HumanApprovalRequired and does not execute.
jq '.steps += [{id: "danger", uses: "foo", depends_on: [], risk: "R2", success: "no",
                command: "kubectl apply -f x.yaml", cwd: "."}]' \
  "$rd/plan.yaml" >"$rd/plan.yaml.tmp"
mv "$rd/plan.yaml.tmp" "$rd/plan.yaml"
assert_status 5 "$S" --run "$run_id" danger
jq -es '.[length - 1].event == "HumanApprovalRequired" and .[length - 1].to == "WAITING_APPROVAL"' \
  "$rd/events.jsonl" >/dev/null || fail "approval event missing"

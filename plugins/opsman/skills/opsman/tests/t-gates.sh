#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
R=$SCRIPTS_DIR/record-event.sh

mkdir -p "$repo/.claude/skills/fluxcd"
printf -- '---\nname: fluxcd\ndescription: flux helmrelease troubleshooting\n---\n' \
  >"$repo/.claude/skills/fluxcd/SKILL.md"
"$SCRIPTS_DIR/build-registry.sh"

run_id=$("$SCRIPTS_DIR/init-run.sh" "do it" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$R" --run "$run_id" --event SkillsIndexed

# TaskClassified: refused without problem.yaml; no event appended
assert_status 5 "$R" --run "$run_id" --event TaskClassified
assert_eq "$(wc -l <"$rd/events.jsonl" | tr -d ' ')" 2 "no event on gate failure"
assert_eq "$(jq -r '.status' "$rd/state.json")" UNDERSTANDING
[ ! -d "$repo/.opsman/lock" ] || fail "lock leaked on gate failure"

# scaffold from task "do it" has empty keywords -> still refused
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
assert_status 5 "$R" --run "$run_id" --event TaskClassified
# keywords alone are not enough: domain must be dev|ops
jq '.keywords = ["flux", "helmrelease"]' "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
assert_status 5 "$R" --run "$run_id" --event TaskClassified
# analyst fills it in -> accepted
jq '.keywords = ["flux", "helmrelease"] | .domain = "ops" | .risk = "medium"
    | .acceptance_criteria = ["flux validation passes"]' \
  "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
"$R" --run "$run_id" --event TaskClassified
assert_eq "$(jq -r '.status' "$rd/state.json")" SELECTING

# SkillsSelected: refused without selection file, then without candidates match
assert_status 5 "$R" --run "$run_id" --event SkillsSelected
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "not-a-candidate", role: "primary", reason: "x"}]}' \
  >"$rd/selected-skills.yaml"
assert_status 5 "$R" --run "$run_id" --event SkillsSelected
jq -n '{selected: [{skill: "fluxcd", role: "primary-domain-expert", reason: "only flux skill"}]}' \
  >"$rd/selected-skills.yaml"
"$R" --run "$run_id" --event SkillsSelected
assert_eq "$(jq -r '.status' "$rd/state.json")" PLANNING

# PlanCreated: refused with a cyclic plan, accepted with a sound one
jq -n '{steps: [
  {id: "a", uses: "fluxcd", depends_on: ["b"], risk: "R0", success: "s"},
  {id: "b", uses: "fluxcd", depends_on: ["a"], risk: "R0", success: "s"}
]}' >"$rd/plan.yaml"
assert_status 5 "$R" --run "$run_id" --event PlanCreated
jq -n '{steps: [{id: "fix", uses: "fluxcd", depends_on: [], risk: "R2",
                 success: "validator passes"}]}' >"$rd/plan.yaml"
"$R" --run "$run_id" --event PlanCreated
assert_eq "$(jq -r '.status' "$rd/state.json")" TEST_DESIGN

# TestsDefined: refused without acceptance.yaml, accepted with checks
assert_status 5 "$R" --run "$run_id" --event TestsDefined
jq -n '{checks: [{id: "c1", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$R" --run "$run_id" --event TestsDefined
"$R" --run "$run_id" --event BaselineRecorded
assert_eq "$(jq -r '.status' "$rd/state.json")" IMPLEMENTING

# M3 gates: implementation needs a prepared worktree plus step evidence or a manual summary.
assert_status 5 "$R" --run "$run_id" --event ImplementationCompleted
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
assert_status 5 "$R" --run "$run_id" --event ImplementationCompleted
printf '{"step_id":"fix","evidence":"not-a-real-evidence-dir","command":"true"}\n' >"$sandbox/fake-step.json"
"$R" --run "$run_id" --event StepCompleted --payload "$sandbox/fake-step.json"
assert_status 5 "$R" --run "$run_id" --event ImplementationCompleted
printf '{"manual_summary":"agent edited documentation only"}\n' >"$sandbox/manual1.json"
"$R" --run "$run_id" --event ImplementationCompleted --payload "$sandbox/manual1.json"
assert_eq "$(jq -r '.status' "$rd/state.json")" VALIDATING

# M3 gates: validation completion needs latest AcceptanceChecked evidence.
assert_status 5 "$R" --run "$run_id" --event ValidationCompleted
printf '{"check_id":"c1","evidence":"not-a-real-evidence-dir","expected_exit":0,"actual_exit":0}\n' >"$sandbox/fake-check.json"
"$R" --run "$run_id" --event AcceptanceChecked --payload "$sandbox/fake-check.json"
assert_status 5 "$R" --run "$run_id" --event ValidationCompleted
"$SCRIPTS_DIR/run-tests.sh" --run "$run_id" >/dev/null
"$R" --run "$run_id" --event ValidationCompleted
assert_eq "$(jq -r '.status' "$rd/state.json")" JUDGING

# Waiver path: a second run may pass BaselineRecorded with TDDWaived instead
"$R" --run "$run_id" --event RunAbandoned
run2=$("$SCRIPTS_DIR/init-run.sh" "do it again with flux" | tail -n 1)
rd2=$repo/.opsman/runs/$run2
"$R" --run "$run2" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run2"
jq '.keywords = ["flux"] | .domain = "ops" | .risk = "low"
    | .acceptance_criteria = ["c"]' "$rd2/problem.yaml" >"$rd2/problem.yaml.tmp"
mv "$rd2/problem.yaml.tmp" "$rd2/problem.yaml"
"$R" --run "$run2" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run2"
jq -n '{selected: [{skill: "fluxcd", role: "primary-domain-expert", reason: "match"}]}' \
  >"$rd2/selected-skills.yaml"
"$R" --run "$run2" --event SkillsSelected
jq -n '{steps: [{id: "s1", uses: "fluxcd", depends_on: [], risk: "R0", success: "ok"}]}' \
  >"$rd2/plan.yaml"
"$R" --run "$run2" --event PlanCreated
# no acceptance.yaml: BaselineRecorded refused, waiver without reason refused
assert_status 5 "$R" --run "$run2" --event BaselineRecorded
printf '{"reason": ""}\n' >"$sandbox/w0.json"
"$R" --run "$run2" --event TDDWaived --payload "$sandbox/w0.json"
assert_status 5 "$R" --run "$run2" --event BaselineRecorded
printf '{"reason": "no runnable assertion for a docs-only change"}\n' >"$sandbox/w1.json"
"$R" --run "$run2" --event TDDWaived --payload "$sandbox/w1.json"
"$R" --run "$run2" --event BaselineRecorded
assert_eq "$(jq -r '.status' "$rd2/state.json")" IMPLEMENTING

# a waiver must not survive into a later TEST_DESIGN cycle
"$SCRIPTS_DIR/create-worktree.sh" --run "$run2" >/dev/null
printf '{"manual_summary":"agent completed docs-only waiver path"}\n' >"$sandbox/manual2.json"
"$R" --run "$run2" --event ImplementationCompleted --payload "$sandbox/manual2.json"
"$R" --run "$run2" --event TestFailed
"$R" --run "$run2" --event ReplanRequested
jq -n '{steps: [{id: "s2", uses: "fluxcd", depends_on: [], risk: "R0", success: "ok"}]}' \
  >"$rd2/plan.yaml"
"$R" --run "$run2" --event PlanCreated
assert_status 5 "$R" --run "$run2" --event BaselineRecorded
printf '{"reason": "still no runnable assertion after replan"}\n' >"$sandbox/w2.json"
"$R" --run "$run2" --event TDDWaived --payload "$sandbox/w2.json"
"$R" --run "$run2" --event BaselineRecorded
assert_eq "$(jq -r '.status' "$rd2/state.json")" IMPLEMENTING

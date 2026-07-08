#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
R=$SCRIPTS_DIR/record-event.sh

# defaults written at init
mkskill ".claude/skills/probe" probe "probe fixture skill"
"$SCRIPTS_DIR/build-registry.sh"
run_id=$("$SCRIPTS_DIR/init-run.sh" "budget defaults" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
assert_file "$rd/limits.json"
assert_eq "$(jq -r '.max_iterations' "$rd/limits.json")" 5
assert_eq "$(jq -r '.max_runtime_commands' "$rd/limits.json")" 100
"$R" --run "$run_id" --event RunAbandoned

# unknown keys and malformed values are usage errors (checked before the lock)
assert_status 2 "$SCRIPTS_DIR/init-run.sh" --limit nope=3 "bad key"
assert_status 2 "$SCRIPTS_DIR/init-run.sh" --limit max_iterations=abc "bad value"

# overrides apply
run_id=$("$SCRIPTS_DIR/init-run.sh" --limit max_iterations=2 --limit max_changed_files=1 "budget overrides" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
assert_eq "$(jq -r '.max_iterations' "$rd/limits.json")" 2
assert_eq "$(jq -r '.max_changed_files' "$rd/limits.json")" 1
assert_eq "$(jq -r '.max_failed_attempts_per_hypothesis' "$rd/limits.json")" 2
"$R" --run "$run_id" --event RunAbandoned

# --- max_iterations -----------------------------------------------------------
# 1 iteration allowed: BaselineRecorded consumes it; HypothesisFormed refused.
run_to_implementing --limit max_iterations=1
"$SCRIPTS_DIR/run-step.sh" --run "$run_id" s1 >/dev/null
"$R" --run "$run_id" --event ImplementationCompleted
# make the check fail so TestFailed is truthful: remove the produced file
rm -f "$repo/.opsman/worktrees/$run_id/out.txt"
assert_status 5 "$SCRIPTS_DIR/run-tests.sh" --run "$run_id"
"$R" --run "$run_id" --event TestFailed
printf '{"hypothesis_id":"h1","statement":"out.txt was removed"}\n' >"$sandbox/hyp.json"
assert_status 6 "$R" --run "$run_id" --event HypothesisFormed --payload "$sandbox/hyp.json"
# state unchanged, no event appended (zero trace)
assert_eq "$(jq -r '.status' "$rd/state.json")" DIAGNOSING
# the mechanical way out works
"$R" --run "$run_id" --event BudgetExceeded
assert_eq "$(jq -r '.status' "$rd/state.json")" BLOCKED

# --- per-hypothesis attempts and same-failure-twice ---------------------------
# fresh run; the check always fails identically (command "false", empty output)
run_id=$("$SCRIPTS_DIR/init-run.sh" "loop pathology" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$R" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["probe"] | .domain = "dev" | .risk = "low"
    | .acceptance_criteria = ["never passes"]' "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
"$R" --run "$run_id" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "probe", role: "primary", reason: "fixture"}]}' \
  >"$rd/selected-skills.yaml"
"$R" --run "$run_id" --event SkillsSelected
jq -n '{steps: [{id: "s1", uses: "probe", depends_on: [], risk: "R1", success: "ok",
                 command: "printf done > out.txt", cwd: "."}]}' >"$rd/plan.yaml"
"$R" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "c1", command: "false", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$R" --run "$run_id" --event TestsDefined
"$R" --run "$run_id" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
"$SCRIPTS_DIR/run-step.sh" --run "$run_id" s1 >/dev/null
"$R" --run "$run_id" --event ImplementationCompleted

# first failure cycle
assert_status 5 "$SCRIPTS_DIR/run-tests.sh" --run "$run_id"
"$R" --run "$run_id" --event TestFailed
printf '{"hypothesis_id":"h1","statement":"check is broken"}\n' >"$sandbox/h1.json"
"$R" --run "$run_id" --event HypothesisFormed --payload "$sandbox/h1.json"
printf '{"manual_summary":"retried the same edit"}\n' >"$sandbox/manual-loop.json"
"$R" --run "$run_id" --event ImplementationCompleted --payload "$sandbox/manual-loop.json"

# second identical failure: same-failure-twice now refuses ANY new hypothesis
assert_status 5 "$SCRIPTS_DIR/run-tests.sh" --run "$run_id"
"$R" --run "$run_id" --event TestFailed
printf '{"hypothesis_id":"h2","statement":"different guess, same evidence"}\n' >"$sandbox/h2.json"
assert_status 6 "$R" --run "$run_id" --event HypothesisFormed --payload "$sandbox/h2.json"
# replan is the mechanical way out
"$R" --run "$run_id" --event ReplanRequested
assert_eq "$(jq -r '.status' "$rd/state.json")" REPLANNING
"$R" --run "$run_id" --event RunAbandoned

# --- max_runtime_commands ------------------------------------------------------
run_to_implementing --limit max_runtime_commands=1
"$SCRIPTS_DIR/run-step.sh" --run "$run_id" s1 >/dev/null # evidence #1
assert_status 6 "$SCRIPTS_DIR/collect-evidence.sh" --run "$run_id" --kind step \
  --id extra --risk R0 --cwd . --command "true"
# runners propagate the budget refusal as exit 6, not 5
assert_status 6 "$SCRIPTS_DIR/run-step.sh" --run "$run_id" s1
"$R" --run "$run_id" --event RunAbandoned

# --- max_changed_files ---------------------------------------------------------
run_to_implementing --limit max_changed_files=1
jq '.steps[0].command = "printf a > f1.txt && printf b > f2.txt"' \
  "$rd/plan.yaml" >"$rd/plan.yaml.tmp"
mv "$rd/plan.yaml.tmp" "$rd/plan.yaml"
"$SCRIPTS_DIR/run-step.sh" --run "$run_id" s1 >/dev/null
assert_status 6 "$R" --run "$run_id" --event ImplementationCompleted
assert_eq "$(jq -r '.status' "$rd/state.json")" IMPLEMENTING
"$R" --run "$run_id" --event RunAbandoned

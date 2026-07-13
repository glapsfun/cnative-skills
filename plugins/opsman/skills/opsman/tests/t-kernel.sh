#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
K=$SCRIPTS_DIR/opsman

# no verb / unknown verb / future verb: exit 2
assert_status 2 "$K"
assert_status 2 "$K" frobnicate
assert_status 2 "$K" next
assert_status 2 "$K" judge

# status before any run: exit 2 with guidance
assert_status 2 "$K" status

# start with an unquoted multi-word task must be rejected, not silently truncated
assert_status 2 "$K" start fix the login bug

# start: builds registry and initializes a run
mkdir -p "$repo/.claude/skills/foo"
printf -- '---\nname: foo\ndescription: foo skill\n---\n' >"$repo/.claude/skills/foo/SKILL.md"
run_id=$("$K" start --no-q --base worktree "fix the widget" | tail -n 1)
assert_file "$repo/.opsman/registry/skills.json"
assert_file "$repo/.opsman/runs/$run_id/state.json"
assert_eq "$(command cat "$repo/.opsman/current")" "$run_id"

# status prints the STATE.md of the current run
"$K" status | grep -q DISCOVERING || fail "status missing state"

# record routes to the current run
"$K" record --event SkillsIndexed
"$K" status | grep -q UNDERSTANDING || fail "record did not advance state"

# validate-run on current run passes
"$K" validate-run

# map rebuilds the registry
rm -rf "$repo/.opsman/registry"
"$K" map
assert_file "$repo/.opsman/registry/skills.json"

# next: renders the analyst packet at UNDERSTANDING and scaffolds problem.yaml
run_dir=$repo/.opsman/runs/$run_id
"$K" next | grep -q 'Role: Analyst' || fail "next did not render analyst packet"
assert_file "$run_dir/problem.yaml"

# walk the full M2 loop through the gates
jq '.keywords = ["foo"] | .domain = "dev" | .risk = "low"
    | .acceptance_criteria = ["works"]' \
  "$run_dir/problem.yaml" >"$run_dir/problem.yaml.tmp"
mv "$run_dir/problem.yaml.tmp" "$run_dir/problem.yaml"
answer_questions_auto "$run_dir" "$run_id"
"$K" record --event TaskClassified

# next at SELECTING auto-scores candidates and renders the selector packet
"$K" next | grep -q 'Role: Selector' || fail "next did not render selector packet"
assert_file "$run_dir/candidates.json"
jq -n '{selected: [{skill: "foo", role: "primary-domain-expert", reason: "only match"}]}' \
  >"$run_dir/selected-skills.yaml"
"$K" record --event SkillsSelected

"$K" next | grep -q 'Role: Planner' || fail "next did not render planner packet"
jq -n '{steps: [{id: "s1", uses: "foo", depends_on: [], risk: "R1", success: "done"}]}' \
  >"$run_dir/plan.yaml"
"$K" record --event PlanCreated
jq -n '{checks: [{id: "c1", command: "true", expected_exit: 0}]}' >"$run_dir/acceptance.yaml"
"$K" record --event TestsDefined
"$K" record --event BaselineRecorded
"$K" worktree >/dev/null

# M3+ states render too: the implementer template ships now
"$K" next | grep -q 'Role: Implementer' || fail "next did not render implementer packet"

# next self-heals when the journal is ahead of state.json (crash window)
s=$(jq -r '.seq' "$run_dir/state.json")
ev=$(jq -cn --argjson seq "$((s + 1))" \
  '{seq: $seq, ts: "2026-01-01T00:00:00Z", event: "ImplementationCompleted",
    from: "IMPLEMENTING", to: "VALIDATING", payload: {}}')
printf '%s\n' "$ev" >>"$run_dir/events.jsonl"
"$K" next | grep -q 'Role: Verifier' || fail "next did not self-heal from journal"
assert_eq "$(jq -r '.status' "$run_dir/state.json")" VALIDATING
[ ! -d "$repo/.opsman/lock" ] || fail "next leaked the lock"

# M4: the kernel drives JUDGING to COMPLETED and finalizes mechanically
"$K" validate >/dev/null
"$K" record --event ValidationCompleted
"$K" judge | grep -q 'Role: Oracle' || fail "judge did not render in JUDGING"
jq -n '{
  verdict: "approved",
  score: {acceptance_criteria: 35, automated_tests: 20, specialist_validation: 15,
          adversarial_review: 10, scope_discipline: 10, safety_compliance: 10, total: 100},
  criteria: [{criterion: "works", evidence: "acceptance evidence for c1", met: true}],
  reason: "kernel e2e fixture"
}' >"$sandbox/kernel-verdict.json"
"$K" record --event OracleApproved --payload "$sandbox/kernel-verdict.json"
assert_eq "$(jq -r '.status' "$run_dir/state.json")" COMPLETED
assert_file "$run_dir/result.md"
assert_file "$run_dir/final.patch"

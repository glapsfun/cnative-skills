#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
R=$SCRIPTS_DIR/record-event.sh

# completed run gets result.md + final.patch automatically
run_to_implementing
run_to_judging
jq -n '{
  verdict: "approved",
  score: {acceptance_criteria: 35, automated_tests: 20, specialist_validation: 15,
          adversarial_review: 10, scope_discipline: 10, safety_compliance: 10, total: 100},
  criteria: [{criterion: "probe check passes", evidence: "evidence for c1", met: true}],
  reason: "all green"
}' >"$sandbox/verdict.json"
"$R" --run "$run_id" --event OracleApproved --payload "$sandbox/verdict.json"
assert_file "$rd/result.md"
assert_file "$rd/final.patch"
grep -q 'COMPLETED' "$rd/result.md" || fail "result.md missing final state"
grep -q 'probe check passes' "$rd/result.md" || fail "result.md missing criteria table"
grep -q 'out.txt' "$rd/final.patch" || fail "final.patch missing the worktree change"

# idempotent rerun
"$SCRIPTS_DIR/finalize.sh" "$rd" || fail "finalize rerun failed"

# validate-run flags a terminal run whose result.md was deleted
rm "$rd/result.md"
assert_status 5 "$SCRIPTS_DIR/validate-artifacts.sh" "$rd"
"$SCRIPTS_DIR/finalize.sh" "$rd"
"$SCRIPTS_DIR/validate-artifacts.sh" "$rd" || fail "validate-run failed after finalize"

# blocked-before-worktree run gets a stub patch
run_id=$("$SCRIPTS_DIR/init-run.sh" "goes nowhere" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$R" --run "$run_id" --event RunBlocked
assert_file "$rd/result.md"
grep -q 'no worktree' "$rd/final.patch" || fail "final.patch stub missing"

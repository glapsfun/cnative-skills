#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
K=$SCRIPTS_DIR/opsman

run_to_implementing

# judge is state-guarded: IMPLEMENTING is not JUDGING
assert_status 3 "$K" judge

run_to_judging
"$K" judge | grep -q 'Role: Oracle' || fail "judge did not render the oracle packet"

# invalid artifacts refuse judging
mv "$rd/problem.yaml" "$rd/problem.yaml.bak"
assert_status 5 "$K" judge
mv "$rd/problem.yaml.bak" "$rd/problem.yaml"
"$K" judge >/dev/null || fail "judge did not recover after artifact restore"

# --- verdict payload contract -------------------------------------------------
R=$SCRIPTS_DIR/record-event.sh
verdict_payload() { # verdict total
  jq -n --arg v "$1" --argjson total "$2" '{
    verdict: $v,
    score: {acceptance_criteria: 35, automated_tests: 20, specialist_validation: 15,
            adversarial_review: 10, scope_discipline: 10, safety_compliance: 10,
            total: $total},
    criteria: [{criterion: "probe check passes",
                evidence: "evidence directory for c1", met: true}],
    reason: "fixture verdict"
  }' >"$sandbox/verdict.json"
}

# payload required; verdict must match the event; reason must be non-empty
assert_status 5 "$R" --run "$run_id" --event OracleRejected
verdict_payload approved 100
assert_status 5 "$R" --run "$run_id" --event OracleRejected --payload "$sandbox/verdict.json"
verdict_payload rejected 40
jq '.reason = ""' "$sandbox/verdict.json" >"$sandbox/verdict2.json"
assert_status 5 "$R" --run "$run_id" --event OracleRejected --payload "$sandbox/verdict2.json"

# valid rejection routes to REPLANNING
verdict_payload rejected 40
"$R" --run "$run_id" --event OracleRejected --payload "$sandbox/verdict.json"
assert_eq "$(jq -r '.status' "$rd/state.json")" REPLANNING

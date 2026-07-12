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
# final.patch is a real, applyable patch: unified diff with new-file CONTENT
head -n 1 "$rd/final.patch" | grep -q '^diff --git' || fail "final.patch is not a unified diff"
grep -q '^+done' "$rd/final.patch" || fail "final.patch missing new-file content"
grep -q 'out.txt' "$rd/final.patch" || fail "final.patch missing the worktree change"

# --- ledger: finalize appended one record for the completed run
run1=$run_id
ledger=$repo/.opsman/ledger.jsonl
assert_file "$ledger"
rec=$(jq -cs --arg id "$run1" '[.[] | select(.run_id == $id)] | last' "$ledger")
assert_eq "$(printf '%s\n' "$rec" | jq -r '.status')" COMPLETED "ledger status"
assert_eq "$(printf '%s\n' "$rec" | jq -r '.schema_version')" 1 "ledger schema_version"
assert_eq "$(printf '%s\n' "$rec" | jq -r '.task')" "drive probe task" "ledger task"
assert_eq "$(printf '%s\n' "$rec" | jq -r '.verdict.verdict')" approved "ledger verdict"
assert_eq "$(printf '%s\n' "$rec" | jq -r '.verdict.score.total')" 100 "ledger score"
assert_eq "$(printf '%s\n' "$rec" | jq -r '.skills[0].skill')" probe "ledger skill name"
assert_eq "$(printf '%s\n' "$rec" | jq -r '.skills[0].role')" primary "ledger skill role"
assert_eq "$(printf '%s\n' "$rec" | jq -r '.classification.domain')" dev "ledger classification"
assert_eq "$(printf '%s\n' "$rec" | jq -r '.budget.iterations | join("/")')" "1/5" "ledger iterations"
printf '%s\n' "$rec" | jq -e '.started_at and .ended_at and .recorded_at' >/dev/null \
  || fail "ledger record missing timestamps"

# idempotent rerun
"$SCRIPTS_DIR/finalize.sh" "$rd" || fail "finalize rerun failed"
n=$(jq -cs --arg id "$run1" '[.[] | select(.run_id == $id)] | length' "$ledger")
assert_eq "$n" 1 "re-finalize must not append a duplicate ledger record"

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

# --- ledger: a run blocked before classification gets a degraded record
rec2=$(jq -cs --arg id "$run_id" '[.[] | select(.run_id == $id)] | last' "$ledger")
assert_eq "$(printf '%s\n' "$rec2" | jq -r '.status')" BLOCKED "ledger blocked status"
assert_eq "$(printf '%s\n' "$rec2" | jq -cr '.skills')" '[]' "pre-selection run has no skills"
assert_eq "$(printf '%s\n' "$rec2" | jq -r '.verdict')" null "pre-oracle run has null verdict"
assert_eq "$(printf '%s\n' "$rec2" | jq -r '.classification')" null "pre-classify run has null classification"

# a payload-less pre-M4 oracle event must not crash the verdict renderer
jq -cn '{seq: 99, ts: "2026-01-01T00:00:00Z", event: "OracleNeedsHuman",
  from: "JUDGING", to: "WAITING_APPROVAL", payload: {}}' >>"$rd/events.jsonl"
"$SCRIPTS_DIR/finalize.sh" "$rd" || fail "finalize crashed on payload-less oracle event"
grep -q 'Verdict:' "$rd/result.md" || fail "result.md missing verdict line for bare event"

# --- an unwritable ledger warns but never fails finalize
mv "$ledger" "$ledger.bak"
mkdir "$ledger"
"$SCRIPTS_DIR/finalize.sh" "$rd" || fail "finalize must succeed when the ledger is unwritable"
rmdir "$ledger"
mv "$ledger.bak" "$ledger"

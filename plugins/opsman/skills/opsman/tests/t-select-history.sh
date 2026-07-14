#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

mkskill "$repo/.claude/skills/skillone" skillone "skillone fixture"
mkskill "$repo/.claude/skills/skilltwo" skilltwo "skilltwo fixture"
mkskill "$repo/.claude/skills/skillthree" skillthree "skillthree fixture"
"$SCRIPTS_DIR/build-registry.sh"

# A ledger with history for skillone (1 approved of 1) and skilltwo (0
# approved of 3, plus one aborted run with no verdict at all -- must NOT
# count toward its total); skillthree has no ledger entries. Verdict
# strings match the real oracle.schema.json enum (lowercase), not the
# uppercase placeholders from the design doc.
mkdir -p "$repo/.opsman"
{
  jq -cn '{schema_version: 1, run_id: "ops-1", recorded_at: "2026-01-01T00:00:00Z",
           status: "COMPLETED", task: "t1",
           skills: [{skill: "skillone", role: "primary"}],
           verdict: {verdict: "approved", score: 95}}'
  jq -cn '{schema_version: 1, run_id: "ops-2", recorded_at: "2026-01-01T00:00:00Z",
           status: "COMPLETED", task: "t2",
           skills: [{skill: "skilltwo", role: "primary"}],
           verdict: {verdict: "rejected", score: 40}}'
  jq -cn '{schema_version: 1, run_id: "ops-3", recorded_at: "2026-01-01T00:00:00Z",
           status: "COMPLETED", task: "t3",
           skills: [{skill: "skilltwo", role: "primary"}],
           verdict: {verdict: "rejected", score: 30}}'
  jq -cn '{schema_version: 1, run_id: "ops-4", recorded_at: "2026-01-01T00:00:00Z",
           status: "COMPLETED", task: "t4",
           skills: [{skill: "skilltwo", role: "primary"}],
           verdict: {verdict: "needs_human", score: 60}}'
  jq -cn '{schema_version: 1, run_id: "ops-5", recorded_at: "2026-01-01T00:00:00Z",
           status: "ABANDONED", task: "t5",
           skills: [{skill: "skilltwo", role: "primary"}],
           verdict: null}'
} >"$repo/.opsman/ledger.jsonl"

run_id=$("$SCRIPTS_DIR/init-run.sh" --base worktree "unrelated task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
S=$SCRIPTS_DIR/select-skills.sh

# Empty problem fields zero out the other four signals, isolating
# historical_success as the only score contributor.
jq -n '{goal: "g", domain: "dev", risk: "low",
        keywords: [], tools: [], affected_components: [], file_patterns: [],
        acceptance_criteria: []}' >"$rd/problem.yaml"

"$S" --run "$run_id"
assert_file "$rd/candidates.json"

# skillone: (1 + 2.5) / (1 + 5) = 0.58
one=$(jq -c '.[] | select(.name == "skillone") | .signals.historical_success' "$rd/candidates.json")
assert_eq "$one" '{"weight":0.10,"approved":1,"total":1,"rate":0.58}'

# skilltwo: (0 + 2.5) / (3 + 5) = 0.31 -- three *judged* past runs, none
# approved; the fourth ledger record (ops-5, verdict: null) must not
# inflate total to 4, since it was never judged by the Oracle
two=$(jq -c '.[] | select(.name == "skilltwo") | .signals.historical_success' "$rd/candidates.json")
assert_eq "$two" '{"weight":0.10,"approved":0,"total":3,"rate":0.31}'

# skillthree: no ledger entries -> neutral prior, exactly 0.5
three=$(jq -c '.[] | select(.name == "skillthree") | .signals.historical_success' "$rd/candidates.json")
assert_eq "$three" '{"weight":0.10,"approved":0,"total":0,"rate":0.5}'

# With every other signal zeroed by the empty problem, score is a pure
# function of historical_success: higher rate ranks higher.
scoreof() { jq -r --arg n "$1" '.[] | select(.name == $n) | .score' "$rd/candidates.json"; }
s1=$(scoreof skillone)
s2=$(scoreof skilltwo)
s3=$(scoreof skillthree)
awk -v a="$s1" -v b="$s3" 'BEGIN { exit !(a > b) }' || fail "skillone (0.58) should outscore skillthree (0.5)"
awk -v a="$s3" -v b="$s2" 'BEGIN { exit !(a > b) }' || fail "skillthree (0.5) should outscore skilltwo (0.31)"

# Malformed ledger records (non-array skills, non-object verdict) must be
# tolerated -- excluded from every skill's count, never a crash.
{
  cat "$repo/.opsman/ledger.jsonl"
  jq -cn '{schema_version: 1, run_id: "ops-6", recorded_at: "2026-01-01T00:00:00Z",
           status: "COMPLETED", task: "t6", skills: "oops", verdict: {verdict: "approved"}}'
  jq -cn '{schema_version: 1, run_id: "ops-7", recorded_at: "2026-01-01T00:00:00Z",
           status: "COMPLETED", task: "t7",
           skills: [{skill: "skillone", role: "primary"}], verdict: "weird"}'
} >"$repo/.opsman/ledger.jsonl.tmp"
mv "$repo/.opsman/ledger.jsonl.tmp" "$repo/.opsman/ledger.jsonl"

"$S" --run "$run_id" --force
assert_file "$rd/candidates.json"
one_after=$(jq -c '.[] | select(.name == "skillone") | .signals.historical_success' "$rd/candidates.json")
assert_eq "$one_after" '{"weight":0.10,"approved":1,"total":1,"rate":0.58}' \
  "malformed ledger records must not crash or count toward a skill's history"

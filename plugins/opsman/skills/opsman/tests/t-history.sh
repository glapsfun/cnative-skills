#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# history.sh + `opsman history`: table, --json, per-run lookup, last-wins
# dedupe, invalid-line tolerance, empty ledger, usage errors.
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
H=$SCRIPTS_DIR/history.sh

# --- missing ledger: friendly message, exit 0
out=$("$H" 2>&1) || fail "history must exit 0 with no ledger"
printf '%s' "$out" | grep -q 'no finished runs recorded' || fail "missing-ledger message"

# --- fixtures: two runs; ops-a has two records (last wins) plus a junk line
mkdir -p .opsman
{
  jq -cn '{schema_version: 1, run_id: "ops-a", recorded_at: "2026-07-10T10:00:00Z",
    status: "BLOCKED", task: "task a", classification: null, skills: [],
    verdict: null, budget: {iterations: [1, 5], commands: [3, 100]},
    started_at: "2026-07-10T09:00:00Z", ended_at: "2026-07-10T10:00:00Z"}'
  printf 'this is not json\n'
  jq -cn '{schema_version: 1, run_id: "ops-b", recorded_at: "2026-07-11T11:00:00Z",
    status: "ABANDONED", task: "task b", classification: null, skills: [],
    verdict: null, budget: {iterations: [0, 5], commands: [0, 100]},
    started_at: "2026-07-11T10:30:00Z", ended_at: "2026-07-11T11:00:00Z"}'
  jq -cn '{schema_version: 1, run_id: "ops-a", recorded_at: "2026-07-12T12:00:00Z",
    status: "COMPLETED", task: "task a", classification: {domain: "dev"},
    skills: [{skill: "probe", role: "primary"}],
    verdict: {verdict: "approved", score: {total: 100}},
    budget: {iterations: [2, 5], commands: [9, 100]},
    started_at: "2026-07-10T09:00:00Z", ended_at: "2026-07-12T12:00:00Z"}'
} >.opsman/ledger.jsonl

# --- table: header, deduped, junk skipped, newest first, last wins
out=$("$H")
printf '%s\n' "$out" | grep -q '^RUN' || fail "table header missing"
assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 3 "header + 2 deduped rows"
first_row=$(printf '%s\n' "$out" | sed -n 2p)
printf '%s' "$first_row" | grep -q 'ops-a' || fail "newest run first"
printf '%s' "$first_row" | grep -q 'COMPLETED' || fail "last record wins for ops-a"
printf '%s' "$first_row" | grep -q 'approved' || fail "verdict column"
printf '%s' "$first_row" | grep -q '2/5' || fail "iterations column"
printf '%s\n' "$out" | sed -n 3p | grep -q 'ops-b' || fail "older run second"

# --- --limit caps the table
out=$("$H" --limit 1)
assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2 "header + 1 row with --limit 1"

# --- --json: deduped array, newest first, honors --limit
out=$("$H" --json)
assert_eq "$(printf '%s\n' "$out" | jq 'length')" 2 "--json array length"
assert_eq "$(printf '%s\n' "$out" | jq -r '.[0].run_id')" ops-a "--json newest first"
assert_eq "$(printf '%s\n' "$out" | jq -r '.[0].status')" COMPLETED "--json last wins"
assert_eq "$(printf '%s\n' "$out" | jq -r '.[1].run_id')" ops-b "--json older second"
assert_eq "$("$H" --json --limit 1 | jq 'length')" 1 "--json honors --limit"

# --- per-run lookup: the full record, pretty-printed
out=$("$H" ops-b)
assert_eq "$(printf '%s\n' "$out" | jq -r '.run_id')" ops-b "per-run lookup"
assert_eq "$(printf '%s\n' "$out" | jq -r '.status')" ABANDONED "per-run status"

# --- unknown run id: exit 2, error lists known ids
assert_status 2 "$H" ops-nope
set +e
out=$("$H" ops-nope 2>&1)
set -e
printf '%s' "$out" | grep -q 'ops-a' || fail "unknown-run error must list known run ids"

# --- usage errors: exit 2
assert_status 2 "$H" --nope
assert_status 2 "$H" --limit
assert_status 2 "$H" --limit zero
assert_status 2 "$H" --limit 0
assert_status 2 "$H" ops-a ops-b

# --- dispatcher wiring
"$SCRIPTS_DIR/opsman" history >/dev/null 2>&1 || fail "opsman history wiring"

printf 'ok\n'

#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# resume.sh + `opsman resume`: torn-tail quarantine, journal rebuild,
# pointer repointing, and refusal paths.
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

# --- fixture: run1 driven to IMPLEMENTING (seq 9, worktree present)
run_to_implementing
run1=$run_id
rd1=$rd

# --- dispatcher resume on a healthy active run: handoff + role packet
out=$("$SCRIPTS_DIR/opsman" resume 2>/dev/null)
printf '%s' "$out" | grep -q 'Opsman Handoff' || fail "resume must print the handoff"
assert_file "$rd1/context/9-implementer.md"

# --- torn journal tail: quarantined to events.jsonl.rej, journal valid again
printf '{"seq":10,"ts":"torn' >>"$rd1/events.jsonl"
"$SCRIPTS_DIR/resume.sh" >/dev/null 2>&1
assert_file "$rd1/events.jsonl.rej"
grep -q 'torn' "$rd1/events.jsonl.rej" || fail "torn line must land in events.jsonl.rej"
tail -n 1 "$rd1/events.jsonl" | jq -e . >/dev/null 2>&1 \
  || fail "journal must contain only valid lines after resume"

# --- journal ahead of state.json: resume rebuilds status from the log
jq -cn '{seq: 10, ts: "2026-01-01T00:00:00Z", event: "ImplementationCompleted",
         from: "IMPLEMENTING", to: "VALIDATING", payload: {}}' \
  >>"$rd1/events.jsonl"
"$SCRIPTS_DIR/resume.sh" >/dev/null 2>&1
assert_eq "$(jq -r '.status' "$rd1/state.json")" "VALIDATING" "status rebuilt from journal"
grep -q 'VALIDATING' "$rd1/STATE.md" || fail "STATE.md must be regenerated"

# --- missing pointer / unknown run-id: exit 2, pointer never written
rm .opsman/current
assert_status 2 "$SCRIPTS_DIR/resume.sh"
assert_status 2 "$SCRIPTS_DIR/resume.sh" ops-nonexistent
[ ! -f .opsman/current ] || fail "failed resume must not write the pointer"

# --- resume by id restores the pointer
"$SCRIPTS_DIR/resume.sh" "$run1" >/dev/null 2>&1
assert_eq "$(cat .opsman/current)" "$run1" "resume <id> must repoint .opsman/current"

# --- invalid artifacts: exit 5 (acceptance.yaml gated by BaselineRecorded)
mv "$rd1/acceptance.yaml" "$rd1/acceptance.yaml.bak"
assert_status 5 "$SCRIPTS_DIR/resume.sh"
mv "$rd1/acceptance.yaml.bak" "$rd1/acceptance.yaml"

# --- terminal run: resume points at result.md instead of a packet
"$SCRIPTS_DIR/record-event.sh" --run "$run1" --event RunAbandoned >/dev/null 2>&1
out=$("$SCRIPTS_DIR/opsman" resume 2>/dev/null)
printf '%s' "$out" | grep -q 'result.md' || fail "terminal resume must point at result.md"

# --- two runs: resume <id> switches the pointer both ways
run2=$("$SCRIPTS_DIR/init-run.sh" "second task" | tail -n 1)
assert_eq "$(cat .opsman/current)" "$run2" "init-run points at run2"
"$SCRIPTS_DIR/resume.sh" "$run1" >/dev/null 2>&1
assert_eq "$(cat .opsman/current)" "$run1" "resume repoints to run1"
"$SCRIPTS_DIR/resume.sh" "$run2" >/dev/null 2>&1
assert_eq "$(cat .opsman/current)" "$run2" "resume repoints back to run2"

# --- held lock: exit 4, nothing resumed
mkdir .opsman/lock
assert_status 4 "$SCRIPTS_DIR/resume.sh"
rmdir .opsman/lock

# --- `opsman resume --help`: usage only, no packet rendered, no lock taken
packets_before=$(find .opsman/runs -name '*.md' -path '*/context/*' | wc -l)
"$SCRIPTS_DIR/opsman" resume --help >/dev/null 2>&1 || fail "resume --help must exit 0"
packets_after=$(find .opsman/runs -name '*.md' -path '*/context/*' | wc -l)
assert_eq "$packets_after" "$packets_before" "resume --help must not render a packet"

# --- WAITING_APPROVAL: resume prints the pending approval kind and return state
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event HumanApprovalRequired >/dev/null 2>&1
out=$("$SCRIPTS_DIR/resume.sh" 2>/dev/null)
printf '%s' "$out" | grep -q 'kind: command' || fail "waiting resume must name the approval kind"
printf '%s' "$out" | grep -q 'returns to DISCOVERING' || fail "waiting resume must name return_to"

# --- BLOCKED: resume points at the partial result
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event BudgetExceeded >/dev/null 2>&1
out=$("$SCRIPTS_DIR/resume.sh" 2>/dev/null)
printf '%s' "$out" | grep -q 'BLOCKED' || fail "blocked resume must name the state"
printf '%s' "$out" | grep -q 'result.md' || fail "blocked resume must point at result.md"

# --- flags after a run-id are a usage error, not a silent no-op
assert_status 2 "$SCRIPTS_DIR/resume.sh" "$run2" --help

# --- unterminated but COMPLETE final event: terminated in place, state rebuilt
rd2=.opsman/runs/$run2
printf '%s' '{"seq":4,"ts":"2026-01-01T00:00:10Z","event":"HumanApprovalRequired","from":"BLOCKED","to":"WAITING_APPROVAL","payload":{}}' \
  >>"$rd2/events.jsonl"
out=$("$SCRIPTS_DIR/resume.sh" 2>/dev/null) || fail "resume must heal an unterminated final event"
assert_eq "$(jq -r '.status' "$rd2/state.json")" "WAITING_APPROVAL" "status rebuilt from healed journal"
printf '%s' "$out" | grep -q 'returns to BLOCKED' || fail "healed event must drive the approval note"
[ ! -f "$rd2/events.jsonl.rej" ] || fail "a complete event must not be quarantined"

# --- record refuses to append onto crash residue; resume repairs, then record works
printf '%s' '{"seq":5,"ts":"to' >>"$rd2/events.jsonl"
assert_status 5 "$SCRIPTS_DIR/record-event.sh" --run "$run2" --event RunAbandoned
"$SCRIPTS_DIR/resume.sh" >/dev/null 2>&1
assert_file "$rd2/events.jsonl.rej"
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event RunAbandoned >/dev/null 2>&1 \
  || fail "record must work again after resume repaired the journal"

# --- `opsman next` with no active run: clean exit 2, no lock left behind
rm .opsman/current
assert_status 2 "$SCRIPTS_DIR/opsman" next
[ ! -d .opsman/lock ] || fail "next without a run must not leave the lock behind"

printf 'ok\n'

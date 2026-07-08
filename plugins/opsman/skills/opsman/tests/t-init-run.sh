#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

# usage: empty task is an error
assert_status 2 "$SCRIPTS_DIR/init-run.sh"

run_id=$("$SCRIPTS_DIR/init-run.sh" "fix the widget" | tail -n 1)
case $run_id in
  ops-[0-9]*-*) : ;;
  *) fail "unexpected run id: $run_id" ;;
esac

rd=$repo/.opsman/runs/$run_id
assert_file "$rd/state.json"
assert_file "$rd/STATE.md"
assert_file "$rd/events.jsonl"
assert_file "$rd/handoff.md"
for d in attempts evidence tests reviews oracle context; do
  [ -d "$rd/$d" ] || fail "missing dir: $d"
done

assert_eq "$(jq -r '.status' "$rd/state.json")" DISCOVERING
assert_eq "$(jq -r '.seq' "$rd/state.json")" 1
assert_eq "$(jq -r '.task.raw_input' "$rd/state.json")" "fix the widget"
assert_eq "$(jq -r '.schema_version' "$rd/state.json")" "1.0"

assert_eq "$(jq -r '.event' "$rd/events.jsonl")" RunStarted
assert_eq "$(jq -r '.to' "$rd/events.jsonl")" DISCOVERING
assert_eq "$(jq -r '.from' "$rd/events.jsonl")" null

assert_eq "$(command cat "$repo/.opsman/current")" "$run_id"
grep -qx '\.opsman/' "$repo/.gitignore" || fail ".gitignore not updated"

# second init: .gitignore line is not duplicated
"$SCRIPTS_DIR/init-run.sh" "another task" >/dev/null
assert_eq "$(grep -cx '\.opsman/' "$repo/.gitignore")" 1 "gitignore dedup"

# STATE.md mentions the status
grep -q 'DISCOVERING' "$rd/STATE.md" || fail "STATE.md missing status"
# handoff lists the only legal lifecycle event from DISCOVERING
grep -q 'SkillsIndexed' "$rd/handoff.md" || fail "handoff.md missing legal event"

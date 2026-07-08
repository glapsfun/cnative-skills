#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
run_id=$("$SCRIPTS_DIR/init-run.sh" "task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
V=$SCRIPTS_DIR/validate-artifacts.sh

# usage
assert_status 2 "$V"

# a fresh run validates
"$V" "$rd"

# ...also after a few transitions
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TaskClassified
"$V" "$rd"

# corrupt state.json -> exit 5
cp "$rd/state.json" "$sandbox/state.bak"
printf 'garbage\n' >"$rd/state.json"
assert_status 5 "$V" "$rd"
cp "$sandbox/state.bak" "$rd/state.json"
"$V" "$rd"

# status mismatch with last event -> exit 5
jq '.status = "JUDGING"' "$rd/state.json" >"$rd/state.json.tmp"
mv "$rd/state.json.tmp" "$rd/state.json"
assert_status 5 "$V" "$rd"
cp "$sandbox/state.bak" "$rd/state.json"

# broken seq chain -> exit 5
cp "$rd/events.jsonl" "$sandbox/events.bak"
bad_event=$(tail -n 1 "$rd/events.jsonl" | jq -c '.seq = 99')
printf '%s\n' "$bad_event" >>"$rd/events.jsonl"
assert_status 5 "$V" "$rd"
cp "$sandbox/events.bak" "$rd/events.jsonl"

# missing required file -> exit 5
mv "$rd/handoff.md" "$sandbox/handoff.bak"
assert_status 5 "$V" "$rd"
mv "$sandbox/handoff.bak" "$rd/handoff.md"
"$V" "$rd"

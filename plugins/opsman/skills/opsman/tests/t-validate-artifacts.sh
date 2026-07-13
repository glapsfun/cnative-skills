#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
run_id=$("$SCRIPTS_DIR/init-run.sh" --no-q --base worktree "task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
V=$SCRIPTS_DIR/validate-artifacts.sh

# usage
assert_status 2 "$V"

# a fresh run validates
"$V" "$rd"

# ...also after a few transitions (satisfy the M2 TaskClassified gate)
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["task"] | .domain = "ops"' "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
answer_questions_auto "$rd" "$run_id"
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

# an event whose transition is illegal per the table (or breaks from→to
# continuity) must be rejected even when the seq chain is intact
awk 'NR == 2 { gsub(/"to":"UNDERSTANDING"/, "\"to\":\"IMPLEMENTING\"") } { print }' \
  "$rd/events.jsonl" >"$sandbox/events.tampered"
cp "$sandbox/events.tampered" "$rd/events.jsonl"
assert_status 5 "$V" "$rd"
cp "$sandbox/events.bak" "$rd/events.jsonl"

# missing required file -> exit 5
mv "$rd/handoff.md" "$sandbox/handoff.bak"
assert_status 5 "$V" "$rd"
mv "$sandbox/handoff.bak" "$rd/handoff.md"
"$V" "$rd"

# a gated artifact deleted after its gate passed -> exit 5
mv "$rd/problem.yaml" "$sandbox/problem.bak"
assert_status 5 "$V" "$rd"
mv "$sandbox/problem.bak" "$rd/problem.yaml"
"$V" "$rd"

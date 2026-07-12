#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# WAITING_INPUT state: park/return mechanics, input.return_to bookkeeping.
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
R=$SCRIPTS_DIR/record-event.sh

mkskill ".claude/skills/probe" probe "probe fixture skill"
"$SCRIPTS_DIR/build-registry.sh"
run_id=$("$SCRIPTS_DIR/init-run.sh" "interview probe task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$R" --run "$run_id" --event SkillsIndexed

# --- park from UNDERSTANDING
"$R" --run "$run_id" --event QuestionsAsked
assert_eq "$(jq -r '.status' "$rd/state.json")" "WAITING_INPUT" "park state"
assert_eq "$(jq -r '.input.return_to' "$rd/state.json")" "UNDERSTANDING" "return_to recorded"
assert_eq "$(jq -r '.approval' "$rd/state.json")" "null" "approval field untouched"

# --- return to origin
"$R" --run "$run_id" --event AnswersProvided
assert_eq "$(jq -r '.status' "$rd/state.json")" "UNDERSTANDING" "@return resolved"
assert_eq "$(jq -r '.input' "$rd/state.json")" "null" "input cleared on return"

# --- self-loop event stays in UNDERSTANDING
"$R" --run "$run_id" --event QuestionsSelfAnswered
assert_eq "$(jq -r '.status' "$rd/state.json")" "UNDERSTANDING" "self-loop state"

# --- AnswersProvided outside WAITING_INPUT is illegal (exit 3)
assert_status 3 "$R" --run "$run_id" --event AnswersProvided

# --- crash-sync rebuild derives input.return_to from the journal
"$R" --run "$run_id" --event QuestionsAsked
jq '.seq = 2 | .status = "UNDERSTANDING" | .input = null' "$rd/state.json" >"$rd/state.json.tmp"
mv "$rd/state.json.tmp" "$rd/state.json"
"$SCRIPTS_DIR/opsman" status >/dev/null 2>&1 || true  # status does not sync; use next
cd "$repo" && "$SCRIPTS_DIR/opsman" next >/dev/null
assert_eq "$(jq -r '.status' "$rd/state.json")" "WAITING_INPUT" "sync rebuilt status"
assert_eq "$(jq -r '.input.return_to' "$rd/state.json")" "UNDERSTANDING" "sync rebuilt input.return_to"

printf 'ok t-interview\n'

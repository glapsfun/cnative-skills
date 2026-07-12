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

# --- QuestionsAsked gate: artifact required
assert_status 5 "$R" --run "$run_id" --event QuestionsAsked

# invalid: all questions already answered
jq -n '{schema_version: "1.0", questions: [
  {id: "q1", question: "scope?", why_it_matters: "drives plan",
   answer: "small", answered_by: "human"}]}' >"$rd/questions.yaml"
assert_status 5 "$R" --run "$run_id" --event QuestionsAsked

# invalid: duplicate ids
jq -n '{schema_version: "1.0", questions: [
  {id: "q1", question: "a?", why_it_matters: "w", answer: null, answered_by: null},
  {id: "q1", question: "b?", why_it_matters: "w", answer: null, answered_by: null}]}' \
  >"$rd/questions.yaml"
assert_status 5 "$R" --run "$run_id" --event QuestionsAsked

# invalid: six questions
jq -n '{schema_version: "1.0", questions: [range(6) |
  {id: ("q" + tostring), question: "x?", why_it_matters: "w", answer: null, answered_by: null}]}' \
  >"$rd/questions.yaml"
assert_status 5 "$R" --run "$run_id" --event QuestionsAsked

# valid: unanswered questions -> park
jq -n '{schema_version: "1.0", questions: [
  {id: "q1", question: "scope?", why_it_matters: "drives plan",
   options: ["small", "large"], default: "small", answer: null, answered_by: null},
  {id: "q2", question: "risk appetite?", why_it_matters: "gates approvals",
   answer: null, answered_by: null}]}' >"$rd/questions.yaml"
"$R" --run "$run_id" --event QuestionsAsked
assert_eq "$(jq -r '.status' "$rd/state.json")" "WAITING_INPUT" "park state"
assert_eq "$(jq -r '.input.return_to' "$rd/state.json")" "UNDERSTANDING" "return_to recorded"
assert_eq "$(jq -r '.approval' "$rd/state.json")" "null" "approval field untouched"

# --- AnswersProvided gate: refused while any answer is empty
assert_status 5 "$R" --run "$run_id" --event AnswersProvided
jq '.questions[0].answer = "small" | .questions[0].answered_by = "human"' \
  "$rd/questions.yaml" >"$rd/questions.yaml.tmp"
mv "$rd/questions.yaml.tmp" "$rd/questions.yaml"
assert_status 5 "$R" --run "$run_id" --event AnswersProvided
jq '.questions[1].answer = "low" | .questions[1].answered_by = "human"' \
  "$rd/questions.yaml" >"$rd/questions.yaml.tmp"
mv "$rd/questions.yaml.tmp" "$rd/questions.yaml"
"$R" --run "$run_id" --event AnswersProvided
assert_eq "$(jq -r '.status' "$rd/state.json")" "UNDERSTANDING" "@return resolved"
assert_eq "$(jq -r '.input' "$rd/state.json")" "null" "input cleared on return"

# --- QuestionsSelfAnswered gate: refused in ask-mode runs
assert_status 5 "$R" --run "$run_id" --event QuestionsSelfAnswered

# --- AnswersProvided outside WAITING_INPUT is illegal (exit 3)
assert_status 3 "$R" --run "$run_id" --event AnswersProvided

# --- crash-sync rebuild derives input.return_to from the journal
jq -n '{schema_version: "1.0", questions: [
  {id: "q1", question: "scope?", why_it_matters: "drives plan",
   options: ["small", "large"], default: "small", answer: null, answered_by: null},
  {id: "q2", question: "risk appetite?", why_it_matters: "gates approvals",
   answer: null, answered_by: null}]}' >"$rd/questions.yaml"
"$R" --run "$run_id" --event QuestionsAsked
jq '.seq = 2 | .status = "UNDERSTANDING" | .input = null' "$rd/state.json" >"$rd/state.json.tmp"
mv "$rd/state.json.tmp" "$rd/state.json"
"$SCRIPTS_DIR/opsman" status >/dev/null 2>&1 || true  # status does not sync; use next
cd "$repo" && "$SCRIPTS_DIR/opsman" next >/dev/null
assert_eq "$(jq -r '.status' "$rd/state.json")" "WAITING_INPUT" "sync rebuilt status"
assert_eq "$(jq -r '.input.return_to' "$rd/state.json")" "UNDERSTANDING" "sync rebuilt input.return_to"

printf 'ok t-interview\n'

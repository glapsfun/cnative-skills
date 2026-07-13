#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# WAITING_INPUT state: park/return mechanics, input.return_to bookkeeping.
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
R=$SCRIPTS_DIR/record-event.sh

mkskill ".claude/skills/probe" probe "probe fixture skill"
"$SCRIPTS_DIR/build-registry.sh"
run_id=$("$SCRIPTS_DIR/init-run.sh" --base worktree "interview probe task" | tail -n 1)
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
"$SCRIPTS_DIR/opsman" status >/dev/null 2>&1 || true # status does not sync; use next
cd "$repo" && "$SCRIPTS_DIR/opsman" next >/dev/null
assert_eq "$(jq -r '.status' "$rd/state.json")" "WAITING_INPUT" "sync rebuilt status"
assert_eq "$(jq -r '.input.return_to' "$rd/state.json")" "UNDERSTANDING" "sync rebuilt input.return_to"

# ---------- interview mode recording + TaskClassified gate ----------
repo2=$sandbox/repo2
mkdir -p "$repo2" && git -C "$repo2" init -q \
  && git -C "$repo2" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
cd "$repo2" || fail "cd repo2"
mkskill ".claude/skills/probe" probe "probe fixture skill"
"$SCRIPTS_DIR/build-registry.sh"

# default is ask
ask_id=$("$SCRIPTS_DIR/init-run.sh" --base worktree "ask mode task" | tail -n 1)
ard=$repo2/.opsman/runs/$ask_id
assert_eq "$(jq -r '.interview.mode' "$ard/state.json")" "ask" "default interview mode"
"$R" --run "$ask_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$ask_id"
jq '.keywords = ["probe"] | .domain = "dev" | .risk = "low"
    | .acceptance_criteria = ["ok"]' "$ard/problem.yaml" >"$ard/problem.yaml.tmp"
mv "$ard/problem.yaml.tmp" "$ard/problem.yaml"

# TaskClassified refused: interview has not happened
assert_status 5 "$R" --run "$ask_id" --event TaskClassified

# park, answer, return — then TaskClassified passes
jq -n '{schema_version: "1.0", questions: [
  {id: "q1", question: "target env?", why_it_matters: "selects skills",
   answer: null, answered_by: null}]}' >"$ard/questions.yaml"
"$R" --run "$ask_id" --event QuestionsAsked
jq '.questions[0].answer = "dev" | .questions[0].answered_by = "human"' \
  "$ard/questions.yaml" >"$ard/questions.yaml.tmp"
mv "$ard/questions.yaml.tmp" "$ard/questions.yaml"
"$R" --run "$ask_id" --event AnswersProvided
"$R" --run "$ask_id" --event TaskClassified
assert_eq "$(jq -r '.status' "$ard/state.json")" "SELECTING" "ask-mode run classified"
"$R" --run "$ask_id" --event RunAbandoned

# --no-q records auto mode; self-answer satisfies the gate
auto_id=$("$SCRIPTS_DIR/init-run.sh" --no-q --base worktree "auto mode task" | tail -n 1)
aud=$repo2/.opsman/runs/$auto_id
assert_eq "$(jq -r '.interview.mode' "$aud/state.json")" "auto" "--no-q -> auto"
"$R" --run "$auto_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$auto_id"
jq '.keywords = ["probe"] | .domain = "dev" | .risk = "low"
    | .acceptance_criteria = ["ok"]' "$aud/problem.yaml" >"$aud/problem.yaml.tmp"
mv "$aud/problem.yaml.tmp" "$aud/problem.yaml"
assert_status 5 "$R" --run "$auto_id" --event TaskClassified
jq -n '{schema_version: "1.0", questions: [
  {id: "q1", question: "target env?", why_it_matters: "selects skills",
   answer: "assumed dev", answered_by: "agent"}]}' >"$aud/questions.yaml"
"$R" --run "$auto_id" --event QuestionsSelfAnswered
assert_eq "$(jq -r '.status' "$aud/state.json")" "UNDERSTANDING" "self-loop"
"$R" --run "$auto_id" --event TaskClassified
assert_eq "$(jq -r '.status' "$aud/state.json")" "SELECTING" "auto-mode run classified"

# ---------- replay + resume + packet ----------
"$SCRIPTS_DIR/validate-artifacts.sh" "$aud" || fail "validate-artifacts rejects a legal interview journal"

# wildcard park from SELECTING, resume renders the interviewer packet
jq -n '{schema_version: "1.0", questions: [
  {id: "q1", question: "which cluster?", why_it_matters: "target selection",
   answer: null, answered_by: null}]}' >"$aud/questions.yaml"
"$R" --run "$auto_id" --event QuestionsAsked
assert_eq "$(jq -r '.input.return_to' "$aud/state.json")" "SELECTING" "wildcard park origin"
out=$("$SCRIPTS_DIR/resume.sh" "$auto_id")
printf '%s\n' "$out" | grep -q 'Role: Interviewer' || fail "resume must render the interviewer packet"
printf '%s\n' "$out" | grep -q 'which cluster?' || fail "packet must embed the questions"
grep -q 'Pending questions' "$aud/STATE.md" || fail "STATE.md must surface pending questions"

# questions.yaml deleted after the fact -> validate-artifacts exit 5
mv "$aud/questions.yaml" "$aud/questions.yaml.bak"
assert_status 5 "$SCRIPTS_DIR/validate-artifacts.sh" "$aud"
mv "$aud/questions.yaml.bak" "$aud/questions.yaml"

printf 'ok t-interview\n'

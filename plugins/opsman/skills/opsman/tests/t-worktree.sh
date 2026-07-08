#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
W=$SCRIPTS_DIR/create-worktree.sh
K=$SCRIPTS_DIR/opsman

mkdir -p "$repo/.claude/skills/foo"
printf -- '---\nname: foo\ndescription: foo execution skill\n---\n' \
  >"$repo/.claude/skills/foo/SKILL.md"
"$SCRIPTS_DIR/build-registry.sh"

run_to_implementing() {
  _run_id=$("$SCRIPTS_DIR/init-run.sh" "prepare execution with foo" | tail -n 1)
  _rd=$repo/.opsman/runs/$_run_id
  "$SCRIPTS_DIR/record-event.sh" --run "$_run_id" --event SkillsIndexed
  "$SCRIPTS_DIR/classify.sh" --run "$_run_id"
  jq '.keywords = ["foo"] | .domain = "dev" | .risk = "low"
      | .acceptance_criteria = ["ok"]' "$_rd/problem.yaml" >"$_rd/problem.yaml.tmp"
  mv "$_rd/problem.yaml.tmp" "$_rd/problem.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$_run_id" --event TaskClassified
  "$SCRIPTS_DIR/select-skills.sh" --run "$_run_id"
  jq -n '{selected: [{skill: "foo", role: "primary", reason: "match"}]}' \
    >"$_rd/selected-skills.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$_run_id" --event SkillsSelected
  jq -n '{steps: [{id: "s1", uses: "foo", depends_on: [], risk: "R1", success: "ok"}]}' \
    >"$_rd/plan.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$_run_id" --event PlanCreated
  jq -n '{checks: [{id: "c1", command: "true", expected_exit: 0}]}' >"$_rd/acceptance.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$_run_id" --event TestsDefined
  "$SCRIPTS_DIR/record-event.sh" --run "$_run_id" --event BaselineRecorded
  printf '%s\n' "$_run_id"
}

run_id=$(run_to_implementing)
rd=$repo/.opsman/runs/$run_id

assert_status 2 "$W"
assert_status 5 "$W" --run nosuch

"$W" --run "$run_id"
wt=$(jq -r '.worktree.path' "$rd/state.json")
[ -d "$wt/.git" ] || [ -f "$wt/.git" ] || fail "worktree missing git metadata"
assert_eq "$(jq -r '.worktree.base_revision' "$rd/state.json")" "$(git rev-parse HEAD)"
jq -es 'any(.[]; .event == "WorktreePrepared")' "$rd/events.jsonl" >/dev/null \
  || fail "WorktreePrepared not recorded"

# Idempotent rerun records/verifies without deleting the worktree.
touch "$wt/keep-me"
"$W" --run "$run_id"
[ -f "$wt/keep-me" ] || fail "worktree rerun deleted user file"

# Kernel dispatch accepts an explicit run id.
"$K" worktree "$run_id" >/dev/null

#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
C=$SCRIPTS_DIR/collect-evidence.sh

mkdir -p "$repo/.claude/skills/foo"
printf -- '---\nname: foo\ndescription: foo execution skill\n---\n' \
  >"$repo/.claude/skills/foo/SKILL.md"
"$SCRIPTS_DIR/build-registry.sh"

run_to_implementing() {
  _run_id=$("$SCRIPTS_DIR/init-run.sh" --no-q "capture output with foo" | tail -n 1)
  _rd=$repo/.opsman/runs/$_run_id
  "$SCRIPTS_DIR/record-event.sh" --run "$_run_id" --event SkillsIndexed
  "$SCRIPTS_DIR/classify.sh" --run "$_run_id"
  jq '.keywords = ["foo"] | .domain = "dev" | .risk = "low"
      | .acceptance_criteria = ["ok"]' "$_rd/problem.yaml" >"$_rd/problem.yaml.tmp"
  mv "$_rd/problem.yaml.tmp" "$_rd/problem.yaml"
  answer_questions_auto "$_rd" "$_run_id"
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
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
rd=$repo/.opsman/runs/$run_id
wt=$(jq -r '.worktree.path' "$rd/state.json")

assert_status 2 "$C"

set +e
path=$("$C" --run "$run_id" --kind step --id s1 --risk R1 --cwd . --command 'printf out; printf err >&2')
code=$?
set -e
assert_eq "$code" 0
assert_file "$path/meta.json"
assert_file "$path/stdout.txt"
assert_file "$path/stderr.txt"
assert_eq "$(cat "$path/stdout.txt")" out
assert_eq "$(cat "$path/stderr.txt")" err
jq -e --arg run_id "$run_id" \
  '.run_id == $run_id and .kind == "step" and .id == "s1" and .exit_code == 0' \
  "$path/meta.json" >/dev/null || fail "bad meta"
jq -e '.stdout_sha256 and .stderr_sha256 and .started_at and .ended_at' "$path/meta.json" >/dev/null \
  || fail "hash/timestamp missing"

set +e
path2=$("$C" --run "$run_id" --kind acceptance --id c1 --risk R0 --cwd . --command 'exit 7')
code2=$?
set -e
assert_eq "$code2" 7
jq -e '.exit_code == 7' "$path2/meta.json" >/dev/null || fail "nonzero exit not captured"

printf 'changed\n' >"$wt/file.txt"
path3=$("$C" --run "$run_id" --kind step --id s2 --risk R2 --cwd . --command 'true')
assert_file "$path3/diff.patch"
grep -q 'file.txt' "$path3/diff.patch" || fail "diff missing file"

mkdir -p "$sandbox/outside-cwd"
ln -s "$sandbox/outside-cwd" "$wt/outside-link"
assert_status 5 "$C" --run "$run_id" --kind step --id escape --risk R0 --cwd outside-link --command true

#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# --base workspace modes: flag contract, state field, branch-mode preflights.
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
I=$SCRIPTS_DIR/init-run.sh

mkskill ".claude/skills/probe" probe "probe fixture skill"
# Commit the fixture skill so the branch-mode dirty check (untracked files
# included) sees a genuinely clean tree once dirt.txt is removed — real
# repos have their skills committed; mkskill alone leaves them untracked.
git add .claude
git -c user.name=t -c user.email=t@t commit -q -m fixture
"$SCRIPTS_DIR/build-registry.sh"

# --base is required, and validated
assert_status 2 "$I" --no-q "task without base"
assert_status 2 "$I" --no-q --base bogus "task with bad base"

# worktree mode records the field
wt_id=$("$I" --no-q --base worktree "worktree task" | tail -n 1)
wrd=$repo/.opsman/runs/$wt_id
assert_eq "$(jq -r '.workspace.mode' "$wrd/state.json")" "worktree" "worktree mode recorded"
assert_eq "$(jq -r '.workspace.branch' "$wrd/state.json")" "null" "no branch in worktree mode"
"$SCRIPTS_DIR/record-event.sh" --run "$wt_id" --event RunAbandoned

# branch mode: dirty tree refused
printf 'dirt\n' >"$repo/dirt.txt"
assert_status 3 "$I" --no-q --base branch "branch task dirty"
rm "$repo/dirt.txt"

# branch mode: detached HEAD refused
git checkout -q --detach
assert_status 3 "$I" --no-q --base branch "branch task detached"
git checkout -q -

# branch mode: clean start records the run branch name
br_id=$("$I" --no-q --base branch "branch task" | tail -n 1)
brd=$repo/.opsman/runs/$br_id
assert_eq "$(jq -r '.workspace.mode' "$brd/state.json")" "branch" "branch mode recorded"
assert_eq "$(jq -r '.workspace.branch' "$brd/state.json")" "opsman/$br_id" "run branch name"
"$SCRIPTS_DIR/record-event.sh" --run "$br_id" --event RunAbandoned

# current mode: dirty tree allowed
printf 'dirt\n' >"$repo/dirt.txt"
cur_id=$("$I" --no-q --base current "current task" | tail -n 1)
crd=$repo/.opsman/runs/$cur_id
assert_eq "$(jq -r '.workspace.mode' "$crd/state.json")" "current" "current mode recorded"

"$SCRIPTS_DIR/record-event.sh" --run "$cur_id" --event RunAbandoned
rm "$repo/dirt.txt"
W=$SCRIPTS_DIR/create-worktree.sh

# Local pipeline to IMPLEMENTING honoring the interview + base mode.
to_implementing() { # base-mode
  _ti_id=$("$SCRIPTS_DIR/init-run.sh" --no-q --base "$1" "workspace $1 task" | tail -n 1)
  _ti_rd=$repo/.opsman/runs/$_ti_id
  "$SCRIPTS_DIR/record-event.sh" --run "$_ti_id" --event SkillsIndexed
  "$SCRIPTS_DIR/classify.sh" --run "$_ti_id"
  jq '.keywords = ["probe"] | .domain = "dev" | .risk = "low"
      | .acceptance_criteria = ["ok"]' "$_ti_rd/problem.yaml" >"$_ti_rd/problem.yaml.tmp"
  mv "$_ti_rd/problem.yaml.tmp" "$_ti_rd/problem.yaml"
  answer_questions_auto "$_ti_rd" "$_ti_id"
  "$SCRIPTS_DIR/record-event.sh" --run "$_ti_id" --event TaskClassified
  "$SCRIPTS_DIR/select-skills.sh" --run "$_ti_id"
  jq -n '{selected: [{skill: "probe", role: "primary", reason: "fixture"}]}' \
    >"$_ti_rd/selected-skills.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$_ti_id" --event SkillsSelected
  jq -n '{steps: [{id: "s1", uses: "probe", depends_on: [], risk: "R1", success: "ok",
                   command: "printf done > out.txt", cwd: ".",
                   allowed_files: ["out.txt"]}]}' >"$_ti_rd/plan.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$_ti_id" --event PlanCreated
  jq -n '{checks: [{id: "c1", command: "test -f out.txt", expected_exit: 0}]}' \
    >"$_ti_rd/acceptance.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$_ti_id" --event TestsDefined
  "$SCRIPTS_DIR/record-event.sh" --run "$_ti_id" --event BaselineRecorded
  printf '%s\n' "$_ti_id"
}

# --- branch mode prepare: creates and checks out opsman/<run-id> at base
head_ref_before=$(git symbolic-ref --short HEAD)
b_id=$(to_implementing branch)
b_rd=$repo/.opsman/runs/$b_id
"$W" --run "$b_id" >/dev/null
assert_eq "$(git symbolic-ref --short HEAD)" "opsman/$b_id" "prepare switched to run branch"

# macOS mktemp puts sandboxes under /private; compare resolved paths
assert_eq "$(jq -r '.worktree.path' "$b_rd/state.json")" "$(cd "$repo" && pwd -P)" \
  "branch mode works in repo root"
assert_eq "$(git rev-parse HEAD)" "$(jq -r '.worktree.base_revision' "$b_rd/state.json")" \
  "branch planted at pinned base"
jq -es 'any(.[]; .event == "WorktreePrepared" and .payload.mode == "branch"
        and .payload.branch != null)' "$b_rd/events.jsonl" >/dev/null \
  || fail "WorktreePrepared payload must carry mode+branch"
"$W" --run "$b_id" >/dev/null || fail "branch-mode prepare must be idempotent"
"$SCRIPTS_DIR/record-event.sh" --run "$b_id" --event RunAbandoned
git checkout -q "$head_ref_before"
git branch -q -D "opsman/$b_id"

# --- current mode prepare: baseline snapshot, no checkout change
printf 'preexisting\n' >"$repo/pre.txt"
c_id=$(to_implementing current)
c_rd=$repo/.opsman/runs/$c_id
"$W" --run "$c_id" >/dev/null
assert_eq "$(git symbolic-ref --short HEAD)" "$head_ref_before" "current mode never switches branch"
assert_file "$c_rd/baseline-dirty.tsv"
grep -q "pre.txt" "$c_rd/baseline-dirty.tsv" || fail "baseline must list pre-existing dirty file"
jq -es 'any(.[]; .event == "WorktreePrepared" and .payload.mode == "current")' \
  "$c_rd/events.jsonl" >/dev/null || fail "WorktreePrepared payload must carry mode current"

printf 'ok t-workspace\n'

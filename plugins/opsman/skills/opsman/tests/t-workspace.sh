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

printf 'ok t-workspace\n'

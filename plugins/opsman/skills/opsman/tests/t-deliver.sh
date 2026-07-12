#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# deliver.sh + `opsman deliver`: branch-from-base delivery of final.patch,
# pr-body.md, preconditions, lock, dispatcher wiring.
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
D=$SCRIPTS_DIR/deliver.sh
R=$SCRIPTS_DIR/record-event.sh

# --- fixture: drive a run to COMPLETED (same flow as t-finalize.sh)
run_to_implementing
run_to_judging
jq -n '{
  verdict: "approved",
  score: {acceptance_criteria: 35, automated_tests: 20, specialist_validation: 15,
          adversarial_review: 10, scope_discipline: 10, safety_compliance: 10, total: 100},
  criteria: [{criterion: "probe check passes", evidence: "evidence for c1", met: true}],
  reason: "all green"
}' >"$sandbox/verdict.json"
"$R" --run "$run_id" --event OracleApproved --payload "$sandbox/verdict.json"

base=$(jq -r '.worktree.base_revision' "$rd/state.json")
head_before=$(git rev-parse HEAD)
status_before=$(git status --porcelain)

# --- happy path
"$D" "$run_id" || fail "deliver failed on a COMPLETED run"
branch=opsman/$run_id
git rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1 \
  || fail "branch $branch was not created"
assert_eq "$(git show "$branch:out.txt")" "done" "delivered commit must contain the run's change"
assert_eq "$(git rev-parse "$branch^")" "$base" "branch parent must be the pinned base revision"
assert_eq "$(git rev-parse HEAD)" "$head_before" "user HEAD must be untouched"
assert_eq "$(git status --porcelain)" "$status_before" "user working tree must be unchanged"
git log -1 --format=%s "$branch" | grep -q 'drive probe task' \
  || fail "commit subject must come from the task"
git log -1 --format=%b "$branch" | grep -q "opsman run: $run_id" \
  || fail "commit body must name the run"
git log -1 --format=%b "$branch" | grep -qi 'co-authored' \
  && fail "commit must carry no co-author trailer"
assert_file "$rd/pr-body.md"
grep -q "$run_id" "$rd/pr-body.md" || fail "pr-body.md must name the run"
grep -q 'approved' "$rd/pr-body.md" || fail "pr-body.md must carry the verdict"
n_wt=$(git worktree list | wc -l | tr -d ' ')
assert_eq "$n_wt" 2 "only main tree + run worktree may remain"

# --- re-deliver: branch exists -> exit 2; --branch override works
assert_status 2 "$D" "$run_id"
"$D" "$run_id" --branch other-name || fail "deliver --branch must succeed"
git rev-parse --verify refs/heads/other-name >/dev/null 2>&1 \
  || fail "--branch name was not honored"

# --- invalid branch name -> exit 2; unknown flag -> exit 2; extra args -> exit 2
assert_status 2 "$D" "$run_id" --branch 'bad..name'
assert_status 2 "$D" "$run_id" --nope
assert_status 2 "$D" "$run_id" extra-positional

# --- empty patch on a COMPLETED run -> exit 5
: >"$rd/final.patch"
assert_status 5 "$D" "$run_id" --branch empty-patch
git rev-parse --verify refs/heads/empty-patch >/dev/null 2>&1 \
  && fail "no branch may be created for an empty patch"
"$SCRIPTS_DIR/finalize.sh" "$rd" # regenerate the real patch

# --- non-COMPLETED run -> exit 3
run2=$("$SCRIPTS_DIR/init-run.sh" "not done yet" | tail -n 1)
"$R" --run "$run2" --event RunBlocked >/dev/null 2>&1
assert_status 3 "$D" "$run2"

# --- unknown run -> exit 2
assert_status 2 "$D" ops-does-not-exist

# --- held lock -> exit 4
mkdir .opsman/lock
assert_status 4 "$D" "$run_id" --branch lock-test
rmdir .opsman/lock

# --- dispatcher wiring
"$SCRIPTS_DIR/opsman" deliver "$run_id" --branch via-dispatcher >/dev/null 2>&1 \
  || fail "opsman deliver wiring"
git rev-parse --verify refs/heads/via-dispatcher >/dev/null 2>&1 \
  || fail "dispatcher delivery must create the branch"

printf 'ok\n'

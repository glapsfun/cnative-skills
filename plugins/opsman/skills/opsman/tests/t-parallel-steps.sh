#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# shellcheck disable=SC2034  # OPSMAN_ROOT/OPSMAN_STEP_WORKTREES_DIR are consumed by lib/parallel.sh
# Parallel plan-step execution: ready-steps, step-run, step-land.
. "$(dirname -- "$0")/lib.sh"

# --- unit: lib/scope.sh snapshot_delta --------------------------------------
. "$SCRIPTS_DIR/lib/common.sh"
. "$SCRIPTS_DIR/lib/scope.sh"

pre=$sandbox/pre.tsv
post=$sandbox/post.tsv

# unchanged path: no delta
printf 'aaa\tsame.txt\n' >"$pre"
printf 'aaa\tsame.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "" "unchanged path produces no delta"

# modified path: reported
printf 'aaa\tchanged.txt\n' >"$pre"
printf 'bbb\tchanged.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "$(printf 'bbb\tchanged.txt')" "modified path is delta"

# new path (absent from pre): reported
: >"$pre"
printf 'ccc\tnew.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "$(printf 'ccc\tnew.txt')" "new path is delta"

# mix of changed, new, and unchanged
printf 'aaa\tsame.txt\nbbb\told.txt\n' >"$pre"
printf 'aaa\tsame.txt\nzzz\told.txt\nccc\tnew.txt\n' >"$post"
want=$(printf 'zzz\told.txt\nccc\tnew.txt')
assert_eq "$(snapshot_delta "$pre" "$post")" "$want" "mixed snapshot reports only changed/new paths"

# --- unit: lib/parallel.sh ----------------------------------------------
. "$SCRIPTS_DIR/lib/paths.sh"
. "$SCRIPTS_DIR/lib/parallel.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
OPSMAN_ROOT=$repo
OPSMAN_STEP_WORKTREES_DIR=$repo/.opsman/step-worktrees

# A real run gitignores .opsman/ at init-run.sh time, before any of this
# runs; mirror that precondition so the throwaway-index overlay excludes
# the scratch worktree nested under .opsman/ the same way it would in
# production, instead of git treating it as an embeddable repo.
printf '.opsman/\n' >>.gitignore
git add .gitignore
git -c user.name=t -c user.email=t@t commit -qm "gitignore .opsman"

base=$(git -C "$repo" rev-parse HEAD)
scratch=$(create_step_worktree "run1" "s1" "$base") || fail "create_step_worktree failed"
[ -d "$scratch" ] || fail "scratch worktree not created: $scratch"
assert_eq "$scratch" "$OPSMAN_STEP_WORKTREES_DIR/run1/s1" "scratch path"
git -C "$scratch" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "scratch is not a git worktree"

# overlay: untracked, modified, and deleted-relative-to-HEAD content all sync
printf 'tracked\n' >tracked.txt
git add tracked.txt
git -c user.name=t -c user.email=t@t commit -qm "add tracked"
printf 'changed\n' >tracked.txt
printf 'new\n' >untracked.txt
overlay_worktree "$repo" "$scratch" || fail "overlay_worktree failed"
assert_eq "$(cat "$scratch/tracked.txt")" "changed" "overlay syncs modified tracked file"
assert_eq "$(cat "$scratch/untracked.txt")" "new" "overlay syncs untracked file"
[ ! -e "$scratch/.opsman" ] || fail "overlay must not copy .opsman/"

# re-overlay after a deletion in src removes it from dst too
rm untracked.txt
overlay_worktree "$repo" "$scratch" || fail "overlay_worktree (delete) failed"
[ ! -e "$scratch/untracked.txt" ] || fail "overlay must propagate deletions"

# src worktree itself must be untouched by overlay (throwaway index only)
assert_eq "$(git -C "$repo" status --porcelain | LC_ALL=C sort)" \
  "$(printf ' M tracked.txt')" "overlay must not mutate the src worktree's real state"

remove_step_worktree "run1" "s1"
[ ! -d "$scratch" ] || fail "remove_step_worktree left the directory behind"
git -C "$repo" worktree list | grep -q "s1" && fail "git still tracks the removed scratch worktree"

rm tracked.txt untracked.txt 2>/dev/null || true
git -C "$repo" checkout -q -- tracked.txt 2>/dev/null || true

printf 'ok\n'

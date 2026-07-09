#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# clean.sh + `opsman clean`: dry-run default, --yes removal, survivors.
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

# --- nothing to clean: both modes succeed on an empty control plane
"$SCRIPTS_DIR/clean.sh" >/dev/null 2>&1
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1

# --- fixture: run1 terminal (ABANDONED) with a worktree
run_to_implementing
run1=$run_id
rd1=$rd
wt1=$(jq -r '.worktree.path' "$rd1/state.json")
[ -d "$wt1" ] || fail "fixture worktree missing"
"$SCRIPTS_DIR/record-event.sh" --run "$run1" --event RunAbandoned >/dev/null 2>&1

# --- dry run lists the run and deletes nothing
out=$("$SCRIPTS_DIR/clean.sh" 2>/dev/null)
printf '%s' "$out" | grep -q "$run1" || fail "dry run must list $run1"
[ -d "$rd1" ] || fail "dry run must not delete the run dir"
[ -d "$wt1" ] || fail "dry run must not delete the worktree"

# --- --yes removes run dir, worktree, and the current pointer
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ ! -d "$rd1" ] || fail "run dir survived clean --yes"
[ ! -d "$wt1" ] || fail "worktree survived clean --yes"
[ ! -f .opsman/current ] || fail "current pointer survived clean --yes"
if git worktree list | grep -q "$run1"; then
  fail "git still tracks the removed worktree"
fi

# --- orphan worktree (no matching run) listed and removed
mkdir -p .opsman/worktrees/ops-orphan
out=$("$SCRIPTS_DIR/clean.sh" 2>/dev/null)
printf '%s' "$out" | grep -q 'ops-orphan' || fail "dry run must list the orphan worktree"
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ ! -d .opsman/worktrees/ops-orphan ] || fail "orphan worktree survived clean --yes"

# --- in-flight runs survive
run2=$("$SCRIPTS_DIR/init-run.sh" "still working" | tail -n 1)
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ -d ".opsman/runs/$run2" ] || fail "in-flight run must survive clean"
assert_eq "$(cat .opsman/current)" "$run2" "in-flight pointer must survive"

# --- unknown flag: usage exit 2; dispatcher wiring works
assert_status 2 "$SCRIPTS_DIR/clean.sh" --nope
"$SCRIPTS_DIR/opsman" clean >/dev/null 2>&1

printf 'ok\n'

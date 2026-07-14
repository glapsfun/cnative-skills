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

# --- the ledger survives clean --yes and still names the removed run
assert_file .opsman/ledger.jsonl
n=$(jq -cs --arg id "$run1" '[.[] | select(.run_id == $id)] | length' .opsman/ledger.jsonl)
assert_eq "$n" 1 "ledger must retain the record for the cleaned run"

# --- orphan worktree (no matching run) listed and removed
mkdir -p .opsman/worktrees/ops-orphan
out=$("$SCRIPTS_DIR/clean.sh" 2>/dev/null)
printf '%s' "$out" | grep -q 'ops-orphan' || fail "dry run must list the orphan worktree"
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ ! -d .opsman/worktrees/ops-orphan ] || fail "orphan worktree survived clean --yes"

# --- in-flight runs survive
run2=$("$SCRIPTS_DIR/init-run.sh" --base worktree "still working" | tail -n 1)
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ -d ".opsman/runs/$run2" ] || fail "in-flight run must survive clean"
assert_eq "$(cat .opsman/current)" "$run2" "in-flight pointer must survive"

# --- BLOCKED runs survive: resumable state, never a clean target
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event BudgetExceeded >/dev/null 2>&1
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ -d ".opsman/runs/$run2" ] || fail "BLOCKED run must survive clean"
assert_eq "$(cat .opsman/current)" "$run2" "pointer to a BLOCKED run must survive"

# --- held lock: exit 4
mkdir .opsman/lock
assert_status 4 "$SCRIPTS_DIR/clean.sh"
rmdir .opsman/lock

# --- dangling pointer: listed by dry run, removed by --yes
printf 'ops-gone\n' >.opsman/current
out=$("$SCRIPTS_DIR/clean.sh" 2>/dev/null)
printf '%s' "$out" | grep -q 'dangling run pointer: ops-gone' || fail "dry run must list the dangling pointer"
[ -f .opsman/current ] || fail "dry run must not remove the pointer"
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ ! -f .opsman/current ] || fail "dangling pointer survived clean --yes"

# --- empty pointer file counts as dangling too
printf '' >.opsman/current
out=$("$SCRIPTS_DIR/clean.sh" 2>/dev/null)
printf '%s' "$out" | grep -q 'dangling run pointer: <empty>' || fail "empty pointer must be listed as dangling"
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ ! -f .opsman/current ] || fail "empty pointer survived clean --yes"

# --- unrecorded worktree of a finished run is listed with the run, not deleted unannounced
run3=$("$SCRIPTS_DIR/init-run.sh" --base worktree "third task" | tail -n 1)
"$SCRIPTS_DIR/record-event.sh" --run "$run3" --event RunAbandoned >/dev/null 2>&1
mkdir -p ".opsman/worktrees/$run3"
out=$("$SCRIPTS_DIR/clean.sh" 2>/dev/null)
printf '%s' "$out" | grep "run $run3" | grep -q "worktrees/$run3" \
  || fail "dry run must attribute the unrecorded worktree to its run"
if printf '%s' "$out" | grep -q "orphan worktree: .*$run3"; then
  fail "an attributable worktree must not be listed as an orphan"
fi
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ ! -d ".opsman/runs/$run3" ] || fail "run3 survived clean --yes"
[ ! -d ".opsman/worktrees/$run3" ] || fail "unrecorded worktree survived clean --yes"

# --- orphaned step-worktrees (crash mid-batch, no run dir) -----------------
mkdir -p .opsman/step-worktrees/ops-orphan-run/some-step
out=$("$SCRIPTS_DIR/clean.sh" 2>/dev/null)
printf '%s' "$out" | grep -q 'step-worktrees/ops-orphan-run' \
  || fail "dry run must list orphaned step-worktrees"
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ ! -d .opsman/step-worktrees/ops-orphan-run ] \
  || fail "orphaned step-worktrees survived clean --yes"

# --- step-worktrees belonging to a run being cleaned are swept too ---------
run_to_implementing
run4=$run_id
rd4=$rd
mkdir -p "$rd4/../../step-worktrees/$run4/leftover-step"
"$SCRIPTS_DIR/record-event.sh" --run "$run4" --event RunAbandoned >/dev/null 2>&1
"$SCRIPTS_DIR/clean.sh" --yes >/dev/null 2>&1
[ ! -d ".opsman/step-worktrees/$run4" ] \
  || fail "finished run's step-worktrees survived clean --yes"

# --- unknown flag: usage exit 2; dispatcher wiring works
assert_status 2 "$SCRIPTS_DIR/clean.sh" --nope
"$SCRIPTS_DIR/opsman" clean >/dev/null 2>&1

printf 'ok\n'

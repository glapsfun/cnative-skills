#!/bin/sh
# Retires finished runs and orphan worktrees. Dry run by default: lists
# targets and deletes nothing; --yes performs the removal. Never prompts —
# the agent shows the dry-run list to the human and re-runs with --yes.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/state.sh"

usage() {
  printf 'usage: clean.sh [--yes]\n' >&2
}

apply=false
while [ $# -gt 0 ]; do
  case $1 in
    --yes)
      apply=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit "$EX_USAGE"
      ;;
  esac
done

need_cmd jq
need_cmd git

"$SCRIPT_DIR/acquire-lock.sh"
trap '"$SCRIPT_DIR/release-lock.sh"' EXIT

found=0
tab=$(printf '\t')
cur=''
if [ -f "$OPSMAN_CURRENT_FILE" ]; then
  cur=$(cat "$OPSMAN_CURRENT_FILE")
fi

# git_worktree_remove_or_rm <path> — shared by remove_worktree and
# remove_step_worktrees_dir, both of which have already applied their own
# containment guard before reaching this point.
git_worktree_remove_or_rm() {
  git -C "$OPSMAN_ROOT" worktree remove --force "$1" 2>/dev/null || rm -rf "${1:?}"
}

remove_worktree() {
  [ -d "$1" ] || return 0
  # Containment guard: the kernel only ever creates worktrees under
  # OPSMAN_WORKTREES_DIR; a state.json corrupted to name any other path
  # must not reach the rm -rf fallback.
  case $1 in
    "$OPSMAN_WORKTREES_DIR"/*) ;;
    *)
      log_warn "refusing to remove worktree outside $OPSMAN_WORKTREES_DIR: $1"
      return 0
      ;;
  esac
  git_worktree_remove_or_rm "$1"
}

remove_step_worktrees_dir() {
  [ -d "$1" ] || return 0
  case $1 in
    "$OPSMAN_STEP_WORKTREES_DIR"/*) ;;
    *)
      log_warn "refusing to remove step-worktrees dir outside $OPSMAN_STEP_WORKTREES_DIR: $1"
      return 0
      ;;
  esac
  for step_wt in "$1"/*/; do
    [ -d "$step_wt" ] || continue
    git_worktree_remove_or_rm "$step_wt"
  done
  rmdir "$1" 2>/dev/null || rm -rf "${1:?}"
}

# Finished runs: only the states in OPSMAN_TERMINAL_STATES. BLOCKED is
# resumable and in-flight runs are the user's work; neither is ever a target.
if [ -d "$OPSMAN_RUNS_DIR" ]; then
  for run_dir in "$OPSMAN_RUNS_DIR"/*/; do
    [ -d "$run_dir" ] || continue
    rid=$(basename "$run_dir")
    if ! run_info=$(jq -r '"\(.status)\t\(.worktree.path // "")"' "$run_dir/state.json" 2>/dev/null); then
      log_warn "skipping $rid: unreadable state.json (inspect or remove it manually)"
      continue
    fi
    status=${run_info%%"$tab"*}
    wt=${run_info#*"$tab"}
    is_terminal_state "$status" || continue
    # A crash can leave the worktree on disk before its WorktreePrepared
    # event landed in state.json; list it with the run so the dry-run
    # listing shows everything --yes would remove (the orphan pass below
    # would otherwise delete it unannounced once the run dir is gone).
    if [ -z "$wt" ] && [ -d "$OPSMAN_WORKTREES_DIR/$rid" ]; then
      wt=$OPSMAN_WORKTREES_DIR/$rid
    fi
    found=1
    printf 'run %s (%s) worktree: %s\n' "$rid" "$status" "${wt:-none}"
    if [ "$apply" = true ]; then
      [ -z "$wt" ] || remove_worktree "$wt"
      remove_step_worktrees_dir "$OPSMAN_STEP_WORKTREES_DIR/$rid"
      rm -rf "${run_dir:?}"
      if [ "$cur" = "$rid" ]; then
        rm -f "$OPSMAN_CURRENT_FILE"
        cur=''
      fi
    fi
  done
fi

# Orphan worktrees: crash leftovers with no run dir to explain them.
if [ -d "$OPSMAN_WORKTREES_DIR" ]; then
  for wt in "$OPSMAN_WORKTREES_DIR"/*/; do
    [ -d "$wt" ] || continue
    wid=$(basename "$wt")
    [ ! -d "$OPSMAN_RUNS_DIR/$wid" ] || continue
    found=1
    printf 'orphan worktree: %s\n' "$wt"
    if [ "$apply" = true ]; then
      remove_worktree "$wt"
    fi
  done
fi

# Orphan step-worktrees: crash-mid-batch leftovers with no run dir.
if [ -d "$OPSMAN_STEP_WORKTREES_DIR" ]; then
  for step_run_dir in "$OPSMAN_STEP_WORKTREES_DIR"/*/; do
    [ -d "$step_run_dir" ] || continue
    swid=$(basename "$step_run_dir")
    [ ! -d "$OPSMAN_RUNS_DIR/$swid" ] || continue
    found=1
    printf 'orphan step-worktrees: %s\n' "$step_run_dir"
    if [ "$apply" = true ]; then
      remove_step_worktrees_dir "$step_run_dir"
    fi
  done
fi

# A pointer naming no existing run — including an empty pointer file —
# makes every pointer-reading verb fail confusingly; retire it.
if [ -f "$OPSMAN_CURRENT_FILE" ] && { [ -z "$cur" ] || [ ! -d "$OPSMAN_RUNS_DIR/$cur" ]; }; then
  found=1
  printf 'dangling run pointer: %s\n' "${cur:-<empty>}"
  if [ "$apply" = true ]; then
    rm -f "$OPSMAN_CURRENT_FILE"
  fi
fi

if [ "$apply" = true ]; then
  git -C "$OPSMAN_ROOT" worktree prune 2>/dev/null || true
fi
if [ "$found" -eq 0 ]; then
  log_info "nothing to clean"
elif [ "$apply" != true ]; then
  log_info "dry run: nothing removed (re-run with --yes to delete)"
fi

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

remove_worktree() {
  [ -d "$1" ] || return 0
  git -C "$OPSMAN_ROOT" worktree remove --force "$1" 2>/dev/null || rm -rf "${1:?}"
}

# Finished runs: only the true terminal states. BLOCKED is resumable and
# in-flight runs are the user's work; neither is ever a target.
if [ -d "$OPSMAN_RUNS_DIR" ]; then
  for run_dir in "$OPSMAN_RUNS_DIR"/*/; do
    [ -d "$run_dir" ] || continue
    rid=$(basename "$run_dir")
    if ! status=$(jq -r '.status' "$run_dir/state.json" 2>/dev/null); then
      log_warn "skipping $rid: unreadable state.json"
      continue
    fi
    case $status in
      COMPLETED | ABANDONED) ;;
      *) continue ;;
    esac
    found=1
    wt=$(jq -r '.worktree.path // empty' "$run_dir/state.json")
    printf 'run %s (%s) worktree: %s\n' "$rid" "$status" "${wt:-none}"
    if [ "$apply" = true ]; then
      [ -z "$wt" ] || remove_worktree "$wt"
      rm -rf "${run_dir:?}"
      if [ -f "$OPSMAN_CURRENT_FILE" ] && [ "$(cat "$OPSMAN_CURRENT_FILE")" = "$rid" ]; then
        rm -f "$OPSMAN_CURRENT_FILE"
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

if [ "$apply" = true ]; then
  git -C "$OPSMAN_ROOT" worktree prune 2>/dev/null || true
  if [ "$found" -eq 0 ]; then
    log_info "nothing to clean"
  fi
else
  if [ "$found" -eq 1 ]; then
    log_info "dry run: nothing removed (re-run with --yes to delete)"
  else
    log_info "nothing to clean"
  fi
fi

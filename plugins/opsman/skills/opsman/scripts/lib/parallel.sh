# shellcheck shell=sh
# Scratch-worktree lifecycle for parallel plan-step execution. A scratch
# worktree is a disposable linked git worktree under
# OPSMAN_STEP_WORKTREES_DIR whose content is made to match the live main
# worktree via a throwaway git index (never a plain file copy, so it stays
# git-native and never touches the source worktree's real index/HEAD).

# overlay_worktree <src-dir> <dst-worktree> — makes <dst-worktree>'s
# tracked+untracked content (respecting .gitignore, so .opsman/ is never
# copied) exactly match <src-dir>'s live state right now. Uses a throwaway
# GIT_INDEX_FILE so <src-dir>'s real index and worktree are never touched.
#
# Known limitation: this has no lock against step-land.sh's own writes to
# <src-dir> (the main worktree). step-land.sh lands one step at a time
# while sibling step-run.sh calls may still be executing, so a multi-file
# land can, in principle, be mid-copy when this runs, letting the resulting
# scratch copy see a torn view of that land. This is scoped by design: a
# correctly-scoped plan (disjoint allowed_files per step) means a step's
# command never reads another step's declared files, so a torn read only
# matters if a step's command scans paths outside its own scope — the same
# thing the scope gate already treats as a plan bug, not a kernel bug.
overlay_worktree() {
  _ow_src=$1
  _ow_dst=$2
  _ow_tmp_index=$(mktemp) || return 1
  # git treats a zero-length existing file as a corrupt index, not a fresh
  # one — remove the mktemp placeholder so git initializes it itself.
  rm -f "$_ow_tmp_index"
  if ! GIT_INDEX_FILE=$_ow_tmp_index git -C "$_ow_src" add -A -- .; then
    rm -f "$_ow_tmp_index"
    return 1
  fi
  _ow_tree=$(GIT_INDEX_FILE=$_ow_tmp_index git -C "$_ow_src" write-tree) || {
    rm -f "$_ow_tmp_index"
    return 1
  }
  rm -f "$_ow_tmp_index"
  git -C "$_ow_dst" read-tree --reset -u "$_ow_tree"
}

# create_step_worktree <run-id> <step-id> <base-ref> — (re)creates the
# scratch worktree for a step, checked out at <base-ref>; prints its path.
# Idempotent: a leftover scratch dir from a prior attempt is discarded first.
create_step_worktree() {
  _cw_dir=$OPSMAN_STEP_WORKTREES_DIR/$1/$2
  _cw_base=$3
  # Common case is a fresh step id with nothing to discard — skip the
  # worktree-remove subprocess entirely rather than always spawning one
  # just to fail.
  if [ -e "$_cw_dir" ]; then
    git -C "$OPSMAN_ROOT" worktree remove --force "$_cw_dir" 2>/dev/null || rm -rf "$_cw_dir"
  fi
  mkdir -p "$(dirname -- "$_cw_dir")"
  git -C "$OPSMAN_ROOT" worktree add -q "$_cw_dir" "$_cw_base" || return 1
  printf '%s\n' "$_cw_dir"
}

# remove_step_worktree <run-id> <step-id> — best-effort cleanup.
remove_step_worktree() {
  _rw_dir=$OPSMAN_STEP_WORKTREES_DIR/$1/$2
  git -C "$OPSMAN_ROOT" worktree remove --force "$_rw_dir" 2>/dev/null || rm -rf "$_rw_dir"
}

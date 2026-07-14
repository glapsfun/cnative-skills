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
  git -C "$OPSMAN_ROOT" worktree remove --force "$_cw_dir" 2>/dev/null || rm -rf "$_cw_dir"
  mkdir -p "$(dirname -- "$_cw_dir")"
  git -C "$OPSMAN_ROOT" worktree add -q "$_cw_dir" "$_cw_base" || return 1
  printf '%s\n' "$_cw_dir"
}

# remove_step_worktree <run-id> <step-id> — best-effort cleanup.
remove_step_worktree() {
  _rw_dir=$OPSMAN_STEP_WORKTREES_DIR/$1/$2
  git -C "$OPSMAN_ROOT" worktree remove --force "$_rw_dir" 2>/dev/null || rm -rf "$_rw_dir"
}

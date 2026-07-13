#!/bin/sh
# Creates or verifies the isolated source worktree for an opsman run.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/scope.sh"

usage() {
  printf 'usage: create-worktree.sh --run <run-id>\n' >&2
}

run_id=''
while [ $# -gt 0 ]; do
  case $1 in
    --run)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      run_id=$2
      shift 2
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
[ -n "$run_id" ] || {
  usage
  exit "$EX_USAGE"
}

need_cmd jq
need_cmd git
run_dir=$OPSMAN_RUNS_DIR/$run_id
[ -f "$run_dir/state.json" ] || die "$EX_ARTIFACT" "no such run: $run_id"

base=$(jq -r '.repository.revision' "$run_dir/state.json")
if [ -z "$base" ] || [ "$base" = "none" ]; then
  die "$EX_ARTIFACT" "run has no git revision"
fi
git -C "$OPSMAN_ROOT" cat-file -e "$base^{commit}" 2>/dev/null \
  || die "$EX_ARTIFACT" "base revision not found: $base"

mode=$(jq -r '.workspace.mode // "worktree"' "$run_dir/state.json")
ws_branch=$(jq -r '.workspace.branch // empty' "$run_dir/state.json")
wt=''
case $mode in
  worktree)
    mkdir -p "$OPSMAN_WORKTREES_DIR"
    wt=$OPSMAN_WORKTREES_DIR/$run_id
    if [ -e "$wt" ]; then
      git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "worktree path exists but is not a git worktree: $wt"
      root_common=$(git -C "$OPSMAN_ROOT" rev-parse --path-format=absolute --git-common-dir)
      wt_common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
      [ "$wt_common" = "$root_common" ] \
        || die "$EX_ARTIFACT" "worktree path belongs to a different repository: $wt"
      got=$(git -C "$wt" rev-parse HEAD)
      [ "$got" = "$base" ] || die "$EX_ARTIFACT" "worktree revision mismatch: $got != $base"
    else
      git -C "$OPSMAN_ROOT" worktree add -q "$wt" "$base" \
        || die "$EX_ARTIFACT" "git worktree add failed for $base"
    fi
    ;;
  branch)
    [ -n "$ws_branch" ] || die "$EX_ARTIFACT" "branch-mode run has no workspace.branch recorded"
    wt=$OPSMAN_ROOT
    if git -C "$OPSMAN_ROOT" rev-parse --verify --quiet "refs/heads/$ws_branch" >/dev/null; then
      # Idempotent re-run: we must already be on the run branch, tip at base
      # (the run never commits; a moved tip means human interference).
      [ "$(git -C "$OPSMAN_ROOT" symbolic-ref --short -q HEAD || :)" = "$ws_branch" ] \
        || die "$EX_ARTIFACT" "run branch $ws_branch exists but is not checked out"
      [ "$(git -C "$OPSMAN_ROOT" rev-parse "refs/heads/$ws_branch")" = "$base" ] \
        || die "$EX_ARTIFACT" "run branch $ws_branch moved off the pinned base $base"
    else
      [ -z "$(git -C "$OPSMAN_ROOT" status --porcelain -- ':(exclude).gitignore' ':(exclude).opsman/' 2>/dev/null)" ] \
        || die "$EX_STATE" "tree went dirty since start — clean it before preparing the run branch"
      [ "$(git -C "$OPSMAN_ROOT" rev-parse HEAD)" = "$base" ] \
        || die "$EX_ARTIFACT" "HEAD moved off the pinned base $base since start — resolve before preparing"
      git -C "$OPSMAN_ROOT" checkout -q -b "$ws_branch" "$base" \
        || die "$EX_ARTIFACT" "could not create run branch $ws_branch"
    fi
    ;;
  current)
    wt=$OPSMAN_ROOT
    [ -f "$run_dir/baseline-dirty.tsv" ] || baseline_snapshot "$OPSMAN_ROOT" "$run_dir/baseline-dirty.tsv"
    ;;
  *)
    die "$EX_ARTIFACT" "unknown workspace mode: $mode"
    ;;
esac

payload=$run_dir/worktree-prepared.json
jq -n --arg path "$wt" --arg base_revision "$base" \
  --arg mode "$mode" --arg branch "$ws_branch" \
  '{path: $path, base_revision: $base_revision, mode: $mode}
   + (if $branch == "" then {} else {branch: $branch} end)' >"$payload.tmp"
mv "$payload.tmp" "$payload"
"$SCRIPT_DIR/record-event.sh" --run "$run_id" --event WorktreePrepared --payload "$payload"
printf '%s\n' "$wt"

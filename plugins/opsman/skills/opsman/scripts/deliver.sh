#!/bin/sh
# Lands a COMPLETED run: applies final.patch in a throwaway detached
# worktree at the run's pinned base revision, commits, and plants a local
# branch there — the user's checkout is never touched, nothing is pushed.
# Also writes <run-dir>/pr-body.md for `gh pr create --body-file`.
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
  printf 'usage: deliver.sh [<run-id>] [--branch <name>]\n' >&2
}

run=''
branch=''
while [ $# -gt 0 ]; do
  case $1 in
    --branch)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      branch=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit "$EX_USAGE"
      ;;
    *)
      [ -z "$run" ] || {
        usage
        exit "$EX_USAGE"
      }
      run=$1
      shift
      ;;
  esac
done

need_cmd jq
need_cmd git

if [ -z "$run" ]; then
  [ -f "$OPSMAN_CURRENT_FILE" ] \
    || die "$EX_USAGE" "no run given and no active run (usage: opsman deliver [<run-id>] [--branch <name>])"
  run=$(cat "$OPSMAN_CURRENT_FILE")
fi
run_dir=$OPSMAN_RUNS_DIR/$run
[ -f "$run_dir/state.json" ] || die "$EX_USAGE" "unknown run: $run"

[ -n "$branch" ] || branch=opsman/$run
git check-ref-format --branch "$branch" >/dev/null 2>&1 \
  || die "$EX_USAGE" "not a valid branch name: $branch"
if git -C "$OPSMAN_ROOT" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
  die "$EX_USAGE" "branch $branch already exists — pick another with --branch, or delete it first"
fi

"$SCRIPT_DIR/acquire-lock.sh"
tmp_wt=''
cleanup() {
  if [ -n "$tmp_wt" ] && [ -d "$tmp_wt" ]; then
    git -C "$OPSMAN_ROOT" worktree remove --force "$tmp_wt" 2>/dev/null \
      || rm -rf "$tmp_wt"
  fi
  "$SCRIPT_DIR/release-lock.sh"
}
trap cleanup EXIT

"$SCRIPT_DIR/validate-artifacts.sh" "$run_dir"

status=$(current_status "$run_dir")
[ "$status" = "COMPLETED" ] \
  || die "$EX_STATE" "run $run is in $status; deliver requires COMPLETED"

patch=$run_dir/final.patch
[ -s "$patch" ] || die "$EX_ARTIFACT" "final.patch is empty — nothing to deliver"
head -n 1 "$patch" | grep -q '^diff --git' \
  || die "$EX_ARTIFACT" "final.patch is a stub (no worktree was created) — nothing to deliver"

task=$(jq -r '.task.raw_input' "$run_dir/state.json")
base=$(jq -r '.worktree.base_revision // .repository.revision // empty' "$run_dir/state.json")
[ -n "$base" ] || die "$EX_ARTIFACT" "no base revision recorded for $run"
git -C "$OPSMAN_ROOT" rev-parse --verify --quiet "$base^{commit}" >/dev/null \
  || die "$EX_ARTIFACT" "base revision $base not found in this repository"

verdict=$(jq -cs '[.[] | select(.event == "OracleApproved")] | last.payload // {}' \
  "$run_dir/events.jsonl")
verdict_line=$(printf '%s\n' "$verdict" | jq -r '
  "verdict: \(.verdict // "approved")"
  + (if (.score | type) == "object" and .score.total != null
     then " (score total: \(.score.total))" else "" end)')

# Subject: first line of the task, hard-capped at 72 chars.
subject=$(printf '%s\n' "$task" | head -n 1 | cut -c1-72)

tmp_wt=$(mktemp -d)
# mktemp creates the dir; `git worktree add` wants to create it itself.
rmdir "$tmp_wt"
git -C "$OPSMAN_ROOT" worktree add --detach --quiet "$tmp_wt" "$base"
git -C "$tmp_wt" apply "$patch"
git -C "$tmp_wt" add -A
msg=$tmp_wt/.opsman-commit-msg
printf '%s\n\nopsman run: %s\n%s\n' "$subject" "$run" "$verdict_line" >"$msg"
git -C "$tmp_wt" commit --quiet -F "$msg"
rm -f "$msg"
sha=$(git -C "$tmp_wt" rev-parse --short HEAD)
git -C "$tmp_wt" branch "$branch"
git -C "$OPSMAN_ROOT" worktree remove --force "$tmp_wt"
tmp_wt=''

{
  printf '# %s\n\n' "$task"
  printf 'Delivered from opsman run `%s` on branch `%s`.\n\n' "$run" "$branch"
  tail -n +2 "$run_dir/result.md"
} >"$run_dir/pr-body.md.tmp"
mv "$run_dir/pr-body.md.tmp" "$run_dir/pr-body.md"

log_info "delivered $run: branch $branch (commit $sha)"
log_info "PR body: $run_dir/pr-body.md"
log_info "next: git merge $branch"
log_info "  or: git push -u origin $branch && gh pr create --title \"$subject\" --body-file $run_dir/pr-body.md"

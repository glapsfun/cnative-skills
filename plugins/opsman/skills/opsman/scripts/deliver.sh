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

ws_mode=$(jq -r '.workspace.mode // "worktree"' "$run_dir/state.json")
ws_branch=$(jq -r '.workspace.branch // empty' "$run_dir/state.json")
if [ "$ws_mode" = "current" ]; then
  die "$EX_USAGE" "run $run used --base current: its changes live uncommitted in your tree and final.patch is the record — commit them yourself"
fi
if [ "$ws_mode" = "branch" ]; then
  [ -z "$branch" ] \
    || die "$EX_USAGE" "--branch is not available for --base branch runs — the run branch is $ws_branch"
  branch=$ws_branch
fi

if [ "$ws_mode" = "worktree" ]; then
  [ -n "$branch" ] || branch=opsman/$run
  git check-ref-format --branch "$branch" >/dev/null 2>&1 \
    || die "$EX_USAGE" "not a valid branch name: $branch"
  if git -C "$OPSMAN_ROOT" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    die "$EX_USAGE" "branch $branch already exists — pick another with --branch, or delete it first"
  fi
  # refs/heads is a directory-like namespace: a name cannot be both a leaf
  # and a prefix. Without this preflight, `git branch` would only fail after
  # the patch has been applied and committed — and with a raw git error.
  _prefix=$branch
  while :; do
    case $_prefix in */*) _prefix=${_prefix%/*} ;; *) break ;; esac
    if git -C "$OPSMAN_ROOT" rev-parse --verify --quiet "refs/heads/$_prefix" >/dev/null; then
      die "$EX_USAGE" "branch $branch conflicts with existing branch $_prefix — pick another with --branch"
    fi
  done
  if [ -n "$(git -C "$OPSMAN_ROOT" for-each-ref "refs/heads/$branch/**" "refs/heads/$branch/*")" ]; then
    die "$EX_USAGE" "branch $branch conflicts with existing branches under $branch/ — pick another with --branch"
  fi
fi

"$SCRIPT_DIR/acquire-lock.sh"
tmp_wt=''
cleanup() {
  if [ -n "$tmp_wt" ] && [ -d "$tmp_wt" ]; then
    git -C "$OPSMAN_ROOT" worktree remove --force "$tmp_wt" 2>/dev/null \
      || {
        rm -rf "$tmp_wt"
        # The rm fallback leaves a stale .git/worktrees entry; prune it
        # (same reconciliation clean.sh performs after its removals).
        git -C "$OPSMAN_ROOT" worktree prune 2>/dev/null || :
      }
  fi
  "$SCRIPT_DIR/release-lock.sh"
}
trap cleanup EXIT

# Status before validate-artifacts: the documented contract is "COMPLETED
# runs only (exit 3 otherwise)" — a non-COMPLETED run with broken
# artifacts must still report 3, not 5 (same order the judge verb uses).
status=$(current_status "$run_dir")
[ "$status" = "COMPLETED" ] \
  || die "$EX_STATE" "run $run is in $status; deliver requires COMPLETED"

"$SCRIPT_DIR/validate-artifacts.sh" "$run_dir"

task=$(jq -r '.task.raw_input' "$run_dir/state.json")
base=$(jq -r '.worktree.base_revision // .repository.revision // empty' "$run_dir/state.json")
[ -n "$base" ] || die "$EX_ARTIFACT" "no base revision recorded for $run"
git -C "$OPSMAN_ROOT" rev-parse --verify --quiet "$base^{commit}" >/dev/null \
  || die "$EX_ARTIFACT" "base revision $base not found in this repository"

verdict_line=$(jq -rs '([.[] | select(.event == "OracleApproved")] | last.payload // {}) as $v
  | "verdict: \($v.verdict // "approved")"
    + (if ($v.score | type) == "object" and $v.score.total != null
       then " (score total: \($v.score.total))" else "" end)' \
  "$run_dir/events.jsonl")

# Subject: first line of the task, capped at 72 characters. jq slices by
# codepoint regardless of locale — `cut -c` under LC_ALL=C would split a
# multibyte character at the boundary.
subject=$(jq -rn --arg t "$task" '$t | split("\n")[0] | .[:72]')

if [ "$ws_mode" = "branch" ]; then
  # Branch mode never used a scratch worktree — the run's changes already
  # live uncommitted on ws_branch in the real checkout; commit them there.
  cur_br=$(git -C "$OPSMAN_ROOT" symbolic-ref --short -q HEAD || :)
  [ "$cur_br" = "$ws_branch" ] \
    || die "$EX_STATE" "checkout is on ${cur_br:-a detached HEAD}, not the run branch $ws_branch — switch back before delivering"
  [ -n "$(git -C "$OPSMAN_ROOT" status --porcelain)" ] \
    || die "$EX_ARTIFACT" "nothing to deliver — the tree on $ws_branch is clean"
  git -C "$OPSMAN_ROOT" add -A
  msg=$run_dir/.opsman-commit-msg
  printf '%s\n\nopsman run: %s\n%s\n' "$subject" "$run" "$verdict_line" >"$msg"
  git -C "$OPSMAN_ROOT" commit --quiet -F "$msg" \
    || die "$EX_DEP" "git could not create the commit (is user.name/user.email configured?)"
  rm -f "$msg"
  sha=$(git -C "$OPSMAN_ROOT" rev-parse --short HEAD)
else
  # .worktree.path is the authoritative "was there ever a worktree" signal —
  # finalize writes a stub final.patch for runs that never created one, and
  # sniffing the patch text would couple deliver to finalize's stub format.
  wt_path=$(jq -r '.worktree.path // empty' "$run_dir/state.json")
  [ -n "$wt_path" ] \
    || die "$EX_ARTIFACT" "no worktree was created for $run — nothing to deliver"
  patch=$run_dir/final.patch
  [ -s "$patch" ] || die "$EX_ARTIFACT" "final.patch is empty — nothing to deliver"

  # The scratch worktree lives under the control plane so a crash leftover
  # (SIGKILL between add and remove skips the trap) is inside the directory
  # `opsman clean`'s orphan sweep already reclaims — never under $TMPDIR.
  tmp_wt=$OPSMAN_WORKTREES_DIR/$run-deliver
  if [ -e "$tmp_wt" ]; then
    git -C "$OPSMAN_ROOT" worktree remove --force "$tmp_wt" 2>/dev/null || rm -rf "$tmp_wt"
    git -C "$OPSMAN_ROOT" worktree prune 2>/dev/null || :
  fi
  git -C "$OPSMAN_ROOT" worktree add --detach --quiet "$tmp_wt" "$base"
  git -C "$tmp_wt" apply "$patch"
  git -C "$tmp_wt" add -A
  msg=$tmp_wt/.opsman-commit-msg
  printf '%s\n\nopsman run: %s\n%s\n' "$subject" "$run" "$verdict_line" >"$msg"
  git -C "$tmp_wt" commit --quiet -F "$msg" \
    || die "$EX_DEP" "git could not create the commit (is user.name/user.email configured?)"
  sha=$(git -C "$tmp_wt" rev-parse --short HEAD)
  git -C "$tmp_wt" branch "$branch" \
    || die "$EX_USAGE" "could not create branch $branch (commit $sha is preserved as a dangling object)"
  git -C "$OPSMAN_ROOT" worktree remove --force "$tmp_wt"
fi

{
  printf '# %s\n\n' "$task"
  # shellcheck disable=SC2016  # backticks are literal markdown, not expansion
  printf 'Delivered from opsman run `%s` on branch `%s`.\n\n' "$run" "$branch"
  # Drop result.md's own title line (matched, not assumed by position) and
  # keep its body: oracle verdict, score table, budget usage, evidence.
  awk 'NR == 1 && /^# Result/ { next } { print }' "$run_dir/result.md"
} >"$run_dir/pr-body.md.tmp"
mv "$run_dir/pr-body.md.tmp" "$run_dir/pr-body.md"

log_info "delivered $run: branch $branch (commit $sha)"
log_info "PR body: $run_dir/pr-body.md"
log_info "next: git merge $branch"
log_info "  or: git push -u origin $branch && gh pr create --title \"$subject\" --body-file $run_dir/pr-body.md"

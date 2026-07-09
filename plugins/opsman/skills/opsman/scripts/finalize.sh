#!/bin/sh
# Writes result.md and final.patch for a run. Idempotent; safe to re-run.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/budget.sh"

usage() {
  printf 'usage: finalize.sh <run-dir>\n' >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi
if [ $# -ne 1 ]; then
  usage
  exit "$EX_USAGE"
fi

need_cmd jq
run_dir=$1
[ -f "$run_dir/state.json" ] || die "$EX_ARTIFACT" "no run at $run_dir"

run_id=$(jq -r '.run_id' "$run_dir/state.json")
status=$(jq -r '.status' "$run_dir/state.json")
task=$(jq -r '.task.raw_input' "$run_dir/state.json")
wt=$(jq -r '.worktree.path // empty' "$run_dir/state.json")

verdict=$(jq -cs '[.[] | select(.event == "OracleApproved" or .event == "OracleRejected"
  or .event == "OracleInconclusive" or .event == "OracleNeedsHuman")] | last // empty' \
  "$run_dir/events.jsonl")
iters=$(jq -rs '[.[] | select(.to == "IMPLEMENTING"
  and (.from == "TEST_DESIGN" or .from == "DIAGNOSING"))] | length' "$run_dir/events.jsonl")
cmds=$(find "$run_dir/evidence" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
max_iters=$(_limit "$run_dir" max_iterations 5)
max_cmds=$(_limit "$run_dir" max_runtime_commands 100)

{
  printf '# Result — %s\n\n' "$run_id"
  printf 'Task: %s\n\n' "$task"
  printf 'Final state: %s\n\n' "$status"
  if [ -n "$verdict" ]; then
    printf '## Oracle verdict\n\n'
    # Pre-M4 logs may carry payload-less oracle events: render what exists,
    # never crash on a missing score or criteria.
    printf '%s\n' "$verdict" | jq -r '
      .payload as $p
      | "Verdict: \($p.verdict // "(unrecorded)") (\(.event), seq \(.seq))",
        "Reason: \($p.reason // "(none)")",
        (if ($p.score | type) == "object" then
           ("",
            "| Category | Score |",
            "| --- | --- |",
            ($p.score | to_entries[] | "| \(.key) | \(.value) |"))
         else empty end),
        (if (($p.criteria | type) == "array") and (($p.criteria | length) > 0) then
           ("",
            "| Criterion | Met | Evidence |",
            "| --- | --- | --- |",
            ($p.criteria[] | "| \(.criterion) | \(.met) | \(.evidence // "-") |"))
         else empty end)'
    printf '\n'
  fi
  printf '## Budget usage\n\n'
  printf -- '- iterations: %s/%s\n' "$iters" "$max_iters"
  printf -- '- runtime commands: %s/%s\n\n' "$cmds" "$max_cmds"
  printf '## Evidence index\n\n'
  if [ -n "$(find "$run_dir/evidence" -mindepth 2 -maxdepth 2 -name meta.json 2>/dev/null | head -n 1)" ]; then
    find "$run_dir/evidence" -mindepth 2 -maxdepth 2 -name meta.json | LC_ALL=C sort \
      | while IFS= read -r meta; do
        jq -r --arg p "$(dirname "$meta")" \
          '"- \(.kind) \(.id): exit=\(.exit_code) command=\(.command) evidence=\($p)"' "$meta"
      done
  else
    printf '(no command evidence captured)\n'
  fi
} >"$run_dir/result.md.tmp"
mv "$run_dir/result.md.tmp" "$run_dir/result.md"

if [ -n "$wt" ] && [ -d "$wt" ]; then
  # A real, applyable patch against the pinned base: a throwaway index copy
  # lets `add -A` capture untracked-file CONTENT (plain `git diff` omits it)
  # without mutating the run worktree's real index. Diffing against the base
  # revision also includes anything committed inside the worktree.
  base=$(jq -r '.worktree.base_revision // .repository.revision // empty' "$run_dir/state.json")
  tmp_index=$(mktemp)
  cp "$(git -C "$wt" rev-parse --absolute-git-dir)/index" "$tmp_index" 2>/dev/null || :
  GIT_INDEX_FILE=$tmp_index git -C "$wt" add -A
  GIT_INDEX_FILE=$tmp_index git -C "$wt" diff --binary --cached "${base:-HEAD}" \
    >"$run_dir/final.patch.tmp"
  rm -f "$tmp_index"
else
  printf 'no worktree was created for this run\n' >"$run_dir/final.patch.tmp"
fi
mv "$run_dir/final.patch.tmp" "$run_dir/final.patch"

log_info "finalized $run_id: $run_dir/result.md, $run_dir/final.patch"

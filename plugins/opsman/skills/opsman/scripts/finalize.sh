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
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/ledger.sh"

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
  # current-mode runs: the human's pre-existing dirty files are not the
  # run's work — exclude them so final.patch records only the run's change.
  # opsman's own control plane (.opsman/, and the uncommitted .gitignore
  # edit that hides it) is excluded unconditionally, in every mode — see
  # opsman_status in lib/scope.sh for why. `,literal` on every exclude: a
  # baselined path with glob metacharacters (e.g. a `[id].tsx` route file)
  # would otherwise also exclude an unrelated sibling path the run itself
  # legitimately changed, silently dropping real work from final.patch.
  set -- ':(exclude,literal).gitignore' ':(exclude,literal).opsman/'
  if [ -f "$run_dir/baseline-dirty.tsv" ]; then
    _fz_tab=$(printf '\t')
    while IFS="$_fz_tab" read -r _fz_h _fz_p; do
      [ -n "$_fz_p" ] || continue
      set -- "$@" ":(exclude,literal)$_fz_p"
    done <"$run_dir/baseline-dirty.tsv"
  fi
  GIT_INDEX_FILE=$tmp_index git -C "$wt" diff --binary --cached "${base:-HEAD}" -- . "$@" \
    >"$run_dir/final.patch.tmp"
  rm -f "$tmp_index"
else
  printf 'no worktree was created for this run\n' >"$run_dir/final.patch.tmp"
fi
mv "$run_dir/final.patch.tmp" "$run_dir/final.patch"

# --- cross-run ledger ---------------------------------------------------
# One derived record per finished run, appended to .opsman/ledger.jsonl —
# outside runs/, so `opsman clean` never removes it. Append-only with
# last-record-per-run_id wins; a re-finalize that changes nothing appends
# nothing. Failures warn: history must never block a run from terminating.
write_ledger_record() {
  _abs_run_dir=$(CDPATH='' cd -- "$run_dir" && pwd) || return 1
  _ledger=$(dirname -- "$(dirname -- "$_abs_run_dir")")/ledger.jsonl
  # Missing artifacts are normal (run ended early); an existing file jq
  # cannot parse is corruption — still record a degraded value, but say so.
  _classification=$(jq -c '.' "$run_dir/problem.yaml" 2>/dev/null) || {
    [ ! -f "$run_dir/problem.yaml" ] \
      || log_warn "ledger: unparseable problem.yaml for $run_id — recording classification: null"
    _classification=null
  }
  [ -n "$_classification" ] || _classification=null
  _skills=$(jq -c '[.selected[] | {skill, role}]' "$run_dir/selected-skills.yaml" 2>/dev/null) || {
    [ ! -f "$run_dir/selected-skills.yaml" ] \
      || log_warn "ledger: unparseable selected-skills.yaml for $run_id — recording no skills"
    _skills='[]'
  }
  [ -n "$_skills" ] || _skills='[]'
  if [ -n "$verdict" ]; then
    _verdict=$(printf '%s\n' "$verdict" \
      | jq -c '{verdict: (.payload.verdict // null), score: (.payload.score // null)}') \
      || return 1
  else
    _verdict=null
  fi
  _started=$(jq -rs '[.[].ts] | first // ""' "$run_dir/events.jsonl") || return 1
  _ended=$(jq -rs '[.[].ts] | last // ""' "$run_dir/events.jsonl") || return 1
  _record=$(jq -cn \
    --arg run_id "$run_id" --arg recorded_at "$(utc_now)" \
    --arg status "$status" --arg task "$task" \
    --arg started "$_started" --arg ended "$_ended" \
    --argjson classification "$_classification" \
    --argjson skills "$_skills" \
    --argjson verdict "$_verdict" \
    --argjson iterations "[$iters, $max_iters]" \
    --argjson commands "[$cmds, $max_cmds]" \
    '{schema_version: 1, run_id: $run_id, recorded_at: $recorded_at,
      status: $status, task: $task, classification: $classification,
      skills: $skills, verdict: $verdict,
      budget: {iterations: $iterations, commands: $commands},
      started_at: $started, ended_at: $ended}') || return 1
  _last=$(ledger_valid_records "$_ledger" \
    | jq -cs --arg id "$run_id" '[.[] | select(.run_id == $id)] | last // empty') || return 1
  if [ -n "$_last" ]; then
    if [ "$(printf '%s\n' "$_record" | jq -cS 'del(.recorded_at)')" \
      = "$(printf '%s\n' "$_last" | jq -cS 'del(.recorded_at)')" ]; then
      return 0
    fi
  fi
  printf '%s\n' "$_record" >>"$_ledger"
}

write_ledger_record \
  || log_warn "ledger append failed for $run_id — history will lack this run"

log_info "finalized $run_id: $run_dir/result.md, $run_dir/final.patch"

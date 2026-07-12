#!/bin/sh
# Read-only view of the cross-run ledger (.opsman/ledger.jsonl). Never
# takes the lock and never reads runs/: the ledger is the sole source, so
# history keeps working after `opsman clean --yes` removes finished runs.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/ledger.sh"

usage() {
  printf 'usage: history.sh [--json] [--limit <n>] [<run-id>]\n' >&2
}

json=false
limit=''
run=''
while [ $# -gt 0 ]; do
  case $1 in
    --json)
      json=true
      shift
      ;;
    --limit)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      limit=$2
      case $limit in
        '' | *[!0-9]*) die "$EX_USAGE" "--limit needs a positive integer (got: $limit)" ;;
      esac
      [ "$limit" -gt 0 ] || die "$EX_USAGE" "--limit needs a positive integer (got: $limit)"
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

records=$(ledger_latest "$OPSMAN_DIR/ledger.jsonl")

if [ -z "$records" ]; then
  [ -z "$run" ] || die "$EX_USAGE" "no ledger record for run $run (no finished runs recorded)"
  log_info "no finished runs recorded"
  exit 0
fi

if [ -n "$run" ]; then
  rec=$(printf '%s\n' "$records" | jq -c --arg id "$run" 'select(.run_id == $id)')
  if [ -z "$rec" ]; then
    known=$(printf '%s\n' "$records" | jq -r '.run_id' | tr '\n' ' ')
    die "$EX_USAGE" "no ledger record for run $run (known: ${known% })"
  fi
  printf '%s\n' "$rec" | jq .
  exit 0
fi

if [ "$json" = true ]; then
  if [ -n "$limit" ]; then
    printf '%s\n' "$records" | jq -s --argjson n "$limit" '.[:$n]'
  else
    printf '%s\n' "$records" | jq -s .
  fi
  exit 0
fi

[ -n "$limit" ] || limit=$(printf '%s\n' "$records" | wc -l | tr -d ' ')
tab=$(printf '\t')
printf '%-32s %-21s %-10s %-9s %-6s %s\n' RUN ENDED STATUS VERDICT ITERS TASK
# try/catch: a shape-corrupt record (e.g. verdict stored as a string) is
# skipped like any other invalid line instead of spilling jq errors.
printf '%s\n' "$records" | head -n "$limit" | jq -r '
  try (
    (.budget.iterations // [null, null]) as $it
    | [.run_id,
       (.ended_at // "-"),
       .status,
       (.verdict.verdict // "-"),
       "\($it[0] // "?")/\($it[1] // "?")",
       (.task | gsub("\\s+"; " ") | if length > 48 then .[:48] + "…" else . end)]
    | @tsv
  ) catch empty' \
  | while IFS=$tab read -r r_id r_end r_st r_vd r_it r_task; do
    printf '%-32s %-21s %-10s %-9s %-6s %s\n' "$r_id" "$r_end" "$r_st" "$r_vd" "$r_it" "$r_task"
  done

#!/bin/sh
# Executes a command in the run worktree and captures structured evidence.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"

usage() {
  printf 'usage: collect-evidence.sh --run <run-id> --kind <kind> --id <id> --risk <R0-R4> --cwd <path> --command <command> [--effective-risk <R0-R4>] [--approval-seq <seq>]\n' >&2
}

run_id=''
kind=''
item_id=''
risk=''
effective=''
rel_cwd='.'
cmd=''
approval_seq=''
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
    --kind)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      kind=$2
      shift 2
      ;;
    --id)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      item_id=$2
      shift 2
      ;;
    --risk)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      risk=$2
      shift 2
      ;;
    --effective-risk)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      effective=$2
      shift 2
      ;;
    --approval-seq)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      approval_seq=$2
      shift 2
      ;;
    --cwd)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      rel_cwd=$2
      shift 2
      ;;
    --command)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      cmd=$2
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
if [ -z "$run_id" ] || [ -z "$kind" ] || [ -z "$item_id" ] || [ -z "$risk" ] || [ -z "$cmd" ]; then
  usage
  exit "$EX_USAGE"
fi
[ -n "$effective" ] || effective=$risk

need_cmd jq
need_cmd git
run_dir=$OPSMAN_RUNS_DIR/$run_id
[ -f "$run_dir/state.json" ] || die "$EX_ARTIFACT" "no such run: $run_id"
wt=$(jq -r '.worktree.path // empty' "$run_dir/state.json")
if [ -z "$wt" ] || [ ! -d "$wt" ]; then
  die "$EX_ARTIFACT" "worktree missing; run: opsman worktree"
fi

case $rel_cwd in
  /* | *..*) die "$EX_ARTIFACT" "cwd must be relative inside the worktree: $rel_cwd" ;;
esac
exec_cwd=$wt/$rel_cwd
[ -d "$exec_cwd" ] || die "$EX_ARTIFACT" "cwd does not exist: $rel_cwd"
wt_phys=$(CDPATH='' cd -- "$wt" && pwd -P) \
  || die "$EX_ARTIFACT" "worktree path is not readable: $wt"
exec_phys=$(CDPATH='' cd -- "$exec_cwd" && pwd -P) \
  || die "$EX_ARTIFACT" "cwd is not readable: $rel_cwd"
case $exec_phys in
  "$wt_phys" | "$wt_phys"/*) ;;
  *) die "$EX_ARTIFACT" "cwd must resolve inside the worktree: $rel_cwd" ;;
esac

mkdir -p "$run_dir/evidence"
# Next seq = highest existing prefix + 1 (a directory count would recycle
# numbers after a deletion), and plain mkdir so a collision — deleted
# predecessor, concurrent collector — fails loudly instead of silently
# rewriting an evidence directory that recorded events already reference.
last=$(find "$run_dir/evidence" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
  | sed -n 's|.*/0*\([0-9][0-9]*\)-.*|\1|p' | sort -n | tail -n 1)
seq=$((${last:-0} + 1))
slug=$(printf '%s-%s' "$kind" "$item_id" | tr -c 'A-Za-z0-9._-' '-' | sed 's/--*/-/g; s/^-//; s/-$//')
out_dir=$run_dir/evidence/$(printf '%03d-%s' "$seq" "$slug")
mkdir "$out_dir" 2>/dev/null || die "$EX_ARTIFACT" "evidence directory collision: $out_dir"

started=$(utc_now)
set +e
(cd "$exec_cwd" && sh -c "$cmd") >"$out_dir/stdout.txt" 2>"$out_dir/stderr.txt"
code=$?
set -e
ended=$(utc_now)

status_out=$(git -C "$wt" status --porcelain --untracked-files=all)
if [ -n "$status_out" ]; then
  {
    printf 'git status --porcelain --untracked-files=all\n'
    printf '%s\n\n' "$status_out"
    git -C "$wt" diff --binary
  } >"$out_dir/diff.patch"
fi

stdout_hash=$(sha256_file "$out_dir/stdout.txt")
stderr_hash=$(sha256_file "$out_dir/stderr.txt")
diff_hash=''
[ -f "$out_dir/diff.patch" ] && diff_hash=$(sha256_file "$out_dir/diff.patch")

jq -n --arg run_id "$run_id" --arg kind "$kind" --arg id "$item_id" \
  --arg command "$cmd" --arg cwd "$rel_cwd" --arg worktree "$wt" \
  --arg started_at "$started" --arg ended_at "$ended" \
  --arg declared_risk "$risk" --arg effective_risk "$effective" \
  --arg approval_seq "$approval_seq" --arg stdout_sha256 "$stdout_hash" \
  --arg stderr_sha256 "$stderr_hash" --arg diff_sha256 "$diff_hash" \
  --argjson exit_code "$code" \
  '{run_id: $run_id, kind: $kind, id: $id, command: $command, cwd: $cwd,
    worktree: $worktree, started_at: $started_at, ended_at: $ended_at,
    exit_code: $exit_code, declared_risk: $declared_risk,
    effective_risk: $effective_risk, approval_seq: $approval_seq,
    stdout_sha256: $stdout_sha256, stderr_sha256: $stderr_sha256}
   | if $diff_sha256 == "" then . else .diff_sha256 = $diff_sha256 end' \
  >"$out_dir/meta.json.tmp"
mv "$out_dir/meta.json.tmp" "$out_dir/meta.json"

printf '%s\n' "$out_dir"
exit "$code"

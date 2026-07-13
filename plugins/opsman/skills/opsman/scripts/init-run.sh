#!/bin/sh
# Initializes a new opsman run in the target repository's .opsman/ dir.
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
  printf 'usage: init-run.sh --base <branch|current|worktree> [--no-q] [--limit key=value ...] [--] "<task description>"\n' >&2
}

need_cmd jq
need_cmd git

limit_overrides='{}'
interview_mode=ask
base_mode=''
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --no-q)
      interview_mode=auto
      shift
      ;;
    --base)
      if [ $# -lt 2 ]; then
        usage
        exit "$EX_USAGE"
      fi
      case $2 in
        branch | current | worktree) base_mode=$2 ;;
        *)
          die "$EX_USAGE" "unknown --base mode: $2 (pick one: branch, current, worktree)"
          ;;
      esac
      shift 2
      ;;
    --limit)
      if [ $# -lt 2 ]; then
        usage
        exit "$EX_USAGE"
      fi
      case $2 in
        max_iterations=* | max_failed_attempts_per_hypothesis=* | \
          max_changed_files=* | max_runtime_commands=*) ;;
        *)
          die "$EX_USAGE" "unknown limit: $2 (known: max_iterations, max_failed_attempts_per_hypothesis, max_changed_files, max_runtime_commands)"
          ;;
      esac
      _lk=${2%%=*}
      _lv=${2#*=}
      case $_lv in
        '' | *[!0-9]*) die "$EX_USAGE" "limit $_lk must be a positive integer, got: $_lv" ;;
      esac
      [ "$_lv" -ge 1 ] || die "$EX_USAGE" "limit $_lk must be a positive integer, got: $_lv"
      limit_overrides=$(jq -cn --argjson cur "$limit_overrides" --arg k "$_lk" \
        --argjson v "$_lv" '$cur + {($k): $v}')
      shift 2
      ;;
    --)
      # end of options: everything after is the task, even if it starts with --
      shift
      break
      ;;
    --*)
      usage
      exit "$EX_USAGE"
      ;;
    *)
      break
      ;;
  esac
done
if [ $# -ne 1 ] || [ -z "$1" ]; then
  usage
  exit "$EX_USAGE"
fi
[ -n "$base_mode" ] \
  || die "$EX_USAGE" "--base <branch|current|worktree> is required — ask the human which workspace mode to use"

"$SCRIPT_DIR/acquire-lock.sh"
trap '"$SCRIPT_DIR/release-lock.sh"' EXIT

# Refuse to orphan an active run: the previous run must reach a resting
# state (COMPLETED, ABANDONED, or BLOCKED) before a new one may start.
if [ -f "$OPSMAN_CURRENT_FILE" ]; then
  prev_run=$(cat "$OPSMAN_CURRENT_FILE")
  prev_state_file=$OPSMAN_RUNS_DIR/$prev_run/state.json
  if [ -f "$prev_state_file" ]; then
    prev_status=$(jq -r '.status' "$prev_state_file")
    case $prev_status in
      COMPLETED | ABANDONED | BLOCKED) ;;
      *)
        die "$EX_STATE" "run $prev_run is still active ($prev_status); abandon it first: opsman record --event RunAbandoned"
        ;;
    esac
  fi
fi

if [ "$base_mode" = "branch" ]; then
  [ -z "$(git -C "$OPSMAN_ROOT" status --porcelain -- ':(exclude).gitignore' ':(exclude).opsman/' 2>/dev/null)" ] \
    || die "$EX_STATE" "--base branch needs a clean tree — commit/stash first, or use --base current|worktree"
  git -C "$OPSMAN_ROOT" symbolic-ref -q HEAD >/dev/null \
    || die "$EX_STATE" "--base branch needs a branch checked out (HEAD is detached) — use --base worktree"
fi

task=$1
ts=$(date -u '+%Y%m%d-%H%M%S')
rand=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')
run_id="ops-$ts-$rand"
run_dir=$OPSMAN_RUNS_DIR/$run_id

mkdir -p "$run_dir/attempts" "$run_dir/evidence" "$run_dir/tests" \
  "$run_dir/reviews" "$run_dir/oracle" "$run_dir/context"

# Budgets are per-run and user-overridable only at start; a missing file
# (pre-M4 runs) means the defaults below.
jq -n --argjson overrides "$limit_overrides" '{
  max_iterations: 5,
  max_failed_attempts_per_hypothesis: 2,
  max_changed_files: 20,
  max_runtime_commands: 100
} + $overrides' >"$run_dir/limits.json.tmp"
mv "$run_dir/limits.json.tmp" "$run_dir/limits.json"

revision=$(git -C "$OPSMAN_ROOT" rev-parse HEAD 2>/dev/null || printf 'none')
# Exclude .gitignore and .opsman/ so opsman's own ignore-entry write (below)
# and control-plane directory never poison the dirty signal of any run.
dirty=false
if [ -n "$(git -C "$OPSMAN_ROOT" status --porcelain -- ':(exclude).gitignore' ':(exclude).opsman/' 2>/dev/null)" ]; then
  dirty=true
fi

jq -n \
  --arg run_id "$run_id" \
  --arg task "$task" \
  --arg root "$OPSMAN_ROOT" \
  --arg revision "$revision" \
  --argjson dirty "$dirty" \
  --arg imode "$interview_mode" \
  --arg wsmode "$base_mode" \
  --arg run_branch "opsman/$run_id" \
  '{
    schema_version: "1.0",
    run_id: $run_id,
    status: "DISCOVERING",
    seq: 1,
    task: { raw_input: $task, domain: null, risk: null, acceptance_criteria: [] },
    repository: { root: $root, revision: $revision, dirty: $dirty },
    approval: null,
    interview: { mode: $imode },
    workspace: { mode: $wsmode,
                 branch: (if $wsmode == "branch" then $run_branch else null end) }
  }' >"$run_dir/state.json.tmp"
mv "$run_dir/state.json.tmp" "$run_dir/state.json"

jq -cn --arg ts "$(utc_now)" --arg task "$task" \
  '{seq: 1, ts: $ts, event: "RunStarted", from: null, to: "DISCOVERING", payload: {task: $task}}' \
  >>"$run_dir/events.jsonl"

printf '%s\n' "$run_id" >"$OPSMAN_CURRENT_FILE.tmp"
mv "$OPSMAN_CURRENT_FILE.tmp" "$OPSMAN_CURRENT_FILE"

# Keep run state out of the target repo's history.
gitignore=$OPSMAN_ROOT/.gitignore
if ! grep -qx '\.opsman/' "$gitignore" 2>/dev/null; then
  # A file without a trailing newline would fuse its last pattern with ours.
  if [ -s "$gitignore" ] && [ -n "$(tail -c 1 "$gitignore")" ]; then
    printf '\n' >>"$gitignore"
  fi
  printf '.opsman/\n' >>"$gitignore"
fi

write_state_md "$run_dir"
write_handoff_md "$run_dir" "$SCRIPT_DIR/state-machine.tsv"

log_info "run $run_id initialized (state: DISCOVERING)"
printf '%s\n' "$run_id"

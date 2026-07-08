# shellcheck shell=sh
# Budget enforcement. Every count is derived from events.jsonl and the
# evidence tree — no counters in state.json. Called by record-event.sh
# under the lock, after transition resolution, before the exit gate; a
# refusal exits 6 (EX_BUDGET) and leaves zero trace.

_limit() { # run-dir key default
  if [ -f "$1/limits.json" ]; then
    jq -r --arg k "$2" --argjson d "$3" '.[$k] // $d' "$1/limits.json"
  else
    printf '%s\n' "$3"
  fi
}

# check_budget <event> <run-dir> <cur-state> <next-state> [payload-file]
check_budget() {
  _cb_event=$1
  _cb_rd=$2
  _cb_cur=$3
  _cb_next=$4
  _cb_payload=${5:-}

  # max_iterations: an iteration is an entry into IMPLEMENTING from
  # TEST_DESIGN or DIAGNOSING (BaselineRecorded / HypothesisFormed). An
  # ApprovalGranted @return into IMPLEMENTING is not a new iteration.
  if [ "$_cb_next" = "IMPLEMENTING" ]; then
    case $_cb_cur in
      TEST_DESIGN | DIAGNOSING)
        _cb_max=$(_limit "$_cb_rd" max_iterations 5)
        _cb_used=$(jq -rs '[.[] | select(.to == "IMPLEMENTING"
          and (.from == "TEST_DESIGN" or .from == "DIAGNOSING"))] | length' \
          "$_cb_rd/events.jsonl")
        [ "$_cb_used" -lt "$_cb_max" ] \
          || die "$EX_BUDGET" "budget: max_iterations reached ($_cb_used/$_cb_max) — record BudgetExceeded or RunAbandoned"
        ;;
    esac
  fi
}

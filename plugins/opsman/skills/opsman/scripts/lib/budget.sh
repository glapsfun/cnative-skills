# shellcheck shell=sh
# Budget enforcement. Every count is derived from events.jsonl and the
# evidence tree — no counters in state.json. Called by record-event.sh
# under the lock, after transition resolution, before the exit gate; a
# refusal exits 6 (EX_BUDGET) and leaves zero trace.

# _limit <run-dir> <key> <default>
# limits.json is user-editable, so trust nothing: unparseable JSON or a
# non-positive-integer value dies (exit 5) instead of feeding garbage into
# a numeric test that would masquerade as a budget refusal.
_limit() {
  _l_val=$3
  if [ -f "$1/limits.json" ]; then
    jq -e . "$1/limits.json" >/dev/null 2>&1 \
      || die "$EX_ARTIFACT" "limits.json is not valid JSON: $1/limits.json"
    _l_read=$(jq -r --arg k "$2" '.[$k] // empty' "$1/limits.json")
    if [ -n "$_l_read" ]; then
      case $_l_read in
        *[!0-9]*) die "$EX_ARTIFACT" "limits.json: $2 must be a positive integer, got: $_l_read" ;;
      esac
      [ "$_l_read" -ge 1 ] \
        || die "$EX_ARTIFACT" "limits.json: $2 must be a positive integer, got: $_l_read"
      _l_val=$_l_read
    fi
  fi
  printf '%s\n' "$_l_val"
}

# _failure_signature <run-dir> <cutoff-seq>
# Signature of the TestFailed cycle ending just before <cutoff-seq>: one
# sorted line per failing AcceptanceChecked since the previous VALIDATING
# entry, carrying check id, actual/expected exits, AND the evidence output
# hashes — hashes alone would make distinct empty-output failures (the norm
# for test commands) collide. Empty when underivable.
_failure_signature() {
  _fs_rd=$1
  _fs_tab=$(printf '\t')
  jq -rs --argjson cut "$2" '
    . as $ev
    | [range(length) | select($ev[.].seq < $cut)] as $idx
    | ([$idx[] | select($ev[.].to == "VALIDATING" and $ev[.].from != "VALIDATING")] | max) as $entry
    | if $entry == null then empty
      else $idx[] | select(. > $entry
          and $ev[.].event == "AcceptanceChecked"
          and $ev[.].payload.actual_exit != $ev[.].payload.expected_exit)
        | $ev[.].payload
        | "\(.check_id)\t\(.actual_exit)\t\(.expected_exit)\t\(.evidence)"
      end' "$_fs_rd/events.jsonl" \
    | while IFS=$_fs_tab read -r _fs_id _fs_actual _fs_expected _fs_ev; do
      _fs_hashes='missing missing'
      if [ -f "$_fs_ev/meta.json" ]; then
        _fs_hashes=$(jq -r '"\(.stdout_sha256) \(.stderr_sha256)"' "$_fs_ev/meta.json")
      fi
      printf '%s %s %s %s\n' "$_fs_id" "$_fs_actual" "$_fs_expected" "$_fs_hashes"
    done | LC_ALL=C sort
}

# _same_failure_twice <run-dir> — 0 when the last two TestFailed cycles
# produced identical failing evidence (the loop is learning nothing).
_same_failure_twice() {
  _sf_rd=$1
  _sf_seqs=$(jq -rs '[.[] | select(.event == "TestFailed") | .seq]
    | if length < 2 then empty else "\(.[-2]) \(.[-1])" end' "$_sf_rd/events.jsonl")
  [ -n "$_sf_seqs" ] || return 1
  _sf_prev=${_sf_seqs% *}
  _sf_last=${_sf_seqs#* }
  _sf_sig_prev=$(_failure_signature "$_sf_rd" "$_sf_prev")
  _sf_sig_last=$(_failure_signature "$_sf_rd" "$_sf_last")
  [ -n "$_sf_sig_last" ] && [ "$_sf_sig_prev" = "$_sf_sig_last" ]
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

  if [ "$_cb_event" = "HypothesisFormed" ]; then
    if _same_failure_twice "$_cb_rd"; then
      die "$EX_BUDGET" "budget: the last two TestFailed cycles produced identical evidence — no new evidence; record ReplanRequested or RunAbandoned"
    fi
    _cb_hid=''
    if [ -n "$_cb_payload" ] && [ -f "$_cb_payload" ]; then
      _cb_hid=$(jq -r '.hypothesis_id // empty' "$_cb_payload" 2>/dev/null || true)
    fi
    if [ -n "$_cb_hid" ]; then
      _cb_max=$(_limit "$_cb_rd" max_failed_attempts_per_hypothesis 2)
      # A hypothesis is charged only with TestFailed events that happened
      # while it was the ACTIVE hypothesis (between its formation and the
      # next HypothesisFormed of any id), summed over its formations —
      # otherwise interleaved hypotheses inflate each other's counts.
      _cb_failed=$(jq -rs --arg id "$_cb_hid" '
        . as $ev
        | [range(length) | select($ev[.].event == "HypothesisFormed")] as $forms
        | [$forms[] | select($ev[.].payload.hypothesis_id == $id)] as $mine
        | [$mine[] as $f
            | ([$forms[] | select(. > $f)] | min) as $next
            | [range(length) | select(. > $f
                and (($next == null) or (. < $next))
                and $ev[.].event == "TestFailed")]
            | length
          ] | add // 0' "$_cb_rd/events.jsonl")
      [ "$_cb_failed" -lt "$_cb_max" ] \
        || die "$EX_BUDGET" "budget: hypothesis $_cb_hid already failed $_cb_failed time(s) (max $_cb_max) — record ReplanRequested"
    fi
  fi

  if [ "$_cb_event" = "ImplementationCompleted" ]; then
    _cb_wt=$(jq -r '.worktree.path // empty' "$_cb_rd/state.json")
    if [ -n "$_cb_wt" ] && [ -d "$_cb_wt" ] && command -v git >/dev/null 2>&1; then
      _cb_max=$(_limit "$_cb_rd" max_changed_files 20)
      _cb_bl=$_cb_rd/baseline-dirty.tsv
      _cb_changed=$(_dirty_paths "$_cb_wt" | LC_ALL=C sort -u | while IFS= read -r _cb_p; do
        [ -n "$_cb_p" ] || continue
        _baseline_has "$_cb_p" "$_cb_bl" || printf '%s\n' "$_cb_p"
      done | wc -l | tr -d ' ')
      [ "$_cb_changed" -le "$_cb_max" ] \
        || die "$EX_BUDGET" "budget: max_changed_files exceeded ($_cb_changed/$_cb_max) — shrink the change or raise the limit at opsman start"
    fi
  fi
}

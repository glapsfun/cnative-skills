# shellcheck shell=sh
# shellcheck disable=SC2016  # backticks in generated markdown are literal text
# State-machine helpers. The transition table is data: state-machine.tsv.

# Terminal states match no table row, not even wildcards.
OPSMAN_TERMINAL_STATES="COMPLETED ABANDONED"

# is_terminal_state <state> — true when the state is in OPSMAN_TERMINAL_STATES.
is_terminal_state() {
  case " $OPSMAN_TERMINAL_STATES " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# role_for_state <roles-table> <state> — prints the owning role, empty if none.
role_for_state() {
  awk -F '\t' -v s="$2" '$1 == s { print $2; exit }' "$1"
}

# render_packet_for_current_state <scripts-dir> <run-id> <run-dir>
# Rescaffold recoverable planning artifacts, then render the role packet.
# Callers must hold the lock and have synced state from the journal.
render_packet_for_current_state() {
  _rp_sd=$1
  _rp_run=$2
  _rp_rd=$3
  _rp_state=$(current_status "$_rp_rd")
  if [ "$_rp_state" = "UNDERSTANDING" ] || [ "$_rp_state" = "SELECTING" ]; then
    # SELECTING also rescaffolds a lost problem.yaml (recovery path).
    [ -f "$_rp_rd/problem.yaml" ] || "$_rp_sd/classify.sh" --run "$_rp_run"
  fi
  if [ "$_rp_state" = "SELECTING" ] && [ ! -f "$_rp_rd/candidates.json" ]; then
    "$_rp_sd/select-skills.sh" --run "$_rp_run"
  fi
  "$_rp_sd/render-context.sh" --run "$_rp_run"
}

# next_state <table> <current> <event>
# Prints the next state, or nothing when the transition is illegal.
next_state() {
  case " $OPSMAN_TERMINAL_STATES " in *" $2 "*) return 0 ;; esac
  awk -F '\t' -v s="$2" -v e="$3" \
    '($1 == s || $1 == "*") && $2 == e { print $3; exit }' "$1"
}

# legal_events <table> <current>
legal_events() {
  case " $OPSMAN_TERMINAL_STATES " in *" $2 "*) return 0 ;; esac
  awk -F '\t' -v s="$2" '$1 == s || $1 == "*" { print $2 }' "$1" | LC_ALL=C sort -u
}

# current_status <run-dir>
current_status() {
  jq -r '.status' "$1/state.json"
}

# sync_state_with_log <run-dir>
# The journal wins: when events.jsonl is ahead of state.json (crash between
# append and rewrite), rebuild status/seq/approval from the log.
# Callers must hold the lock and have sourced common.sh and log.sh.
sync_state_with_log() {
  _sy_rd=$1
  _sy_len=$(wc -l <"$_sy_rd/events.jsonl" | tr -d ' ')
  _sy_seq=$(jq -r '.seq' "$_sy_rd/state.json")
  [ "$_sy_len" -gt "$_sy_seq" ] || return 0
  log_warn "state.json behind event log (seq $_sy_seq < $_sy_len); rebuilding from events"
  _sy_rebuilt=$(jq -cs '
    {status: .[length - 1].to,
     seq: length,
     approval: (reduce .[] as $e (null;
       if $e.to == "WAITING_APPROVAL" and $e.from != "WAITING_APPROVAL" then {return_to: $e.from}
       elif $e.from == "WAITING_APPROVAL" and $e.to != "WAITING_APPROVAL" then null
       else . end)),
     worktree: (reduce .[] as $e (null;
       if $e.event == "WorktreePrepared" then
         {path: $e.payload.path, base_revision: $e.payload.base_revision}
       else . end))}' "$_sy_rd/events.jsonl") \
    || die "$EX_ARTIFACT" "event log unreadable; run: opsman validate-run"
  jq --argjson r "$_sy_rebuilt" \
    '.status = $r.status | .seq = $r.seq | .approval = $r.approval
     | if $r.worktree == null then del(.worktree) else .worktree = $r.worktree end' \
    "$_sy_rd/state.json" >"$_sy_rd/state.json.tmp"
  mv "$_sy_rd/state.json.tmp" "$_sy_rd/state.json"
}

# write_state_md <run-dir> — regenerate the human-readable mirror.
write_state_md() {
  _sm_rd=$1
  jq -r '"# Opsman Run \(.run_id)\n\n- Status: \(.status)\n- Seq: \(.seq)\n- Task: \(.task.raw_input)\n- Repository: \(.repository.root) @ \(.repository.revision) (dirty: \(.repository.dirty))"' \
    "$_sm_rd/state.json" >"$_sm_rd/STATE.md.tmp"
  mv "$_sm_rd/STATE.md.tmp" "$_sm_rd/STATE.md"
}

# write_handoff_md <run-dir> <table> — regenerate the next-agent packet.
write_handoff_md() {
  _ho_rd=$1
  _ho_table=$2
  _ho_status=$(current_status "$_ho_rd")
  {
    printf '# Opsman Handoff\n\n'
    printf -- '- Run: %s\n' "$(jq -r '.run_id' "$_ho_rd/state.json")"
    printf -- '- State: %s\n' "$_ho_status"
    printf -- '- Task: %s\n\n' "$(jq -r '.task.raw_input' "$_ho_rd/state.json")"
    printf 'Legal next events:\n\n'
    legal_events "$_ho_table" "$_ho_status" | sed 's/^/- /'
    printf '\nNext command: `opsman status` for details; record progress with `opsman record --event <Event>`.\n'
  } >"$_ho_rd/handoff.md.tmp"
  mv "$_ho_rd/handoff.md.tmp" "$_ho_rd/handoff.md"
}

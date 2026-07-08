# shellcheck shell=sh
# shellcheck disable=SC2016  # backticks in generated markdown are literal text
# State-machine helpers. The transition table is data: state-machine.tsv.

# Terminal states match no table row, not even wildcards.
OPSMAN_TERMINAL_STATES="COMPLETED ABANDONED"

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

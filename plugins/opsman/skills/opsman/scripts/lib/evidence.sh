# shellcheck shell=sh
# Evidence and approval helpers shared by command runners and gates.

latest_approval_seq() { # run-dir step-id command effective-risk
  jq -rs --arg step_id "$2" --arg command "$3" --arg effective "$4" '
    [.[] | select(.event == "ApprovalGranted"
      and .payload.step_id == $step_id
      and .payload.command == $command
      and .payload.effective_risk == $effective)] | last | .seq // empty
  ' "$1/events.jsonl"
}

evidence_valid() { # schemas-dir run-dir evidence kind id expected-exit-or-empty require-diff
  _ev_sd=$1
  _ev_rd=$2
  _ev_path=$3
  _ev_kind=$4
  _ev_id=$5
  _ev_expected=$6
  _ev_require_diff=${7:-false}

  [ -n "$_ev_path" ] && [ -d "$_ev_path" ] || return 1
  [ -d "$_ev_rd/evidence" ] || return 1

  _ev_root=$(CDPATH='' cd -- "$_ev_rd/evidence" && pwd -P) || return 1
  _ev_phys=$(CDPATH='' cd -- "$_ev_path" && pwd -P) || return 1
  case $_ev_phys in
    "$_ev_root"/*) ;;
    *) return 1 ;;
  esac

  _ev_meta=$_ev_path/meta.json
  [ -f "$_ev_meta" ] && [ -f "$_ev_path/stdout.txt" ] && [ -f "$_ev_path/stderr.txt" ] || return 1
  json_valid "$_ev_meta" || return 1
  schema_check "$_ev_sd/evidence.schema.json" "$_ev_meta" || return 1

  _ev_run_id=$(basename -- "$_ev_rd")
  if [ -n "$_ev_expected" ]; then
    jq -e --arg run_id "$_ev_run_id" --arg kind "$_ev_kind" --arg id "$_ev_id" \
      --argjson expected "$_ev_expected" \
      '.run_id == $run_id and .kind == $kind and .id == $id and .exit_code == $expected' \
      "$_ev_meta" >/dev/null 2>&1 || return 1
  else
    jq -e --arg run_id "$_ev_run_id" --arg kind "$_ev_kind" --arg id "$_ev_id" \
      '.run_id == $run_id and .kind == $kind and .id == $id' \
      "$_ev_meta" >/dev/null 2>&1 || return 1
  fi

  _ev_stdout_hash=$(sha256_file "$_ev_path/stdout.txt")
  _ev_stderr_hash=$(sha256_file "$_ev_path/stderr.txt")
  jq -e --arg stdout_hash "$_ev_stdout_hash" --arg stderr_hash "$_ev_stderr_hash" \
    '.stdout_sha256 == $stdout_hash and .stderr_sha256 == $stderr_hash' \
    "$_ev_meta" >/dev/null 2>&1 || return 1

  _ev_has_meta_diff=$(jq -r '.diff_sha256 // empty' "$_ev_meta")
  if [ -n "$_ev_has_meta_diff" ]; then
    [ -f "$_ev_path/diff.patch" ] || return 1
    _ev_diff_hash=$(sha256_file "$_ev_path/diff.patch")
    [ "$_ev_diff_hash" = "$_ev_has_meta_diff" ] || return 1
  elif [ -f "$_ev_path/diff.patch" ]; then
    return 1
  fi

  if [ "$_ev_require_diff" = "true" ]; then
    jq -e '((.diff_sha256 // "") | length > 0)' "$_ev_meta" >/dev/null 2>&1 || return 1
  fi

  jq -e '(.effective_risk == "R3" or .effective_risk == "R4")
          and (((.approval_seq // "") | tostring | length) == 0)' \
    "$_ev_meta" >/dev/null 2>&1 && return 1

  return 0
}

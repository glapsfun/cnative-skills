# shellcheck shell=sh
# Cross-run ledger helpers. The ledger (.opsman/ledger.jsonl) is derived,
# append-only data: one JSON record per finished run, last record per
# run_id wins. Invalid lines are skipped, never repaired — the ledger is
# regenerable by re-running finalize.sh while the run dir exists.

# ledger_valid_records <ledger-file> — emit each line that parses as a
# JSON object with a string run_id; silently skip everything else.
# Missing file emits nothing.
ledger_valid_records() {
  [ -f "$1" ] || return 0
  # Single pass: -R + fromjson? skips unparseable lines inside jq itself,
  # instead of forking one jq per line of an ever-growing file.
  jq -cR 'fromjson? | select(type == "object" and (.run_id | type) == "string")' \
    "$1" 2>/dev/null || :
}

# ledger_latest <ledger-file> — deduped records (last per run_id wins),
# newest ended_at first, one compact JSON object per line.
ledger_latest() {
  ledger_valid_records "$1" | jq -cs '
    reduce .[] as $r ({}; .[$r.run_id] = $r)
    | [.[]] | sort_by(.ended_at // "") | reverse | .[]'
}

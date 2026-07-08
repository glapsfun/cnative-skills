# shellcheck shell=sh
# Exit gates: each planning phase owes an artifact before its exit event.
# Called by record-event.sh under the lock, after transition resolution,
# before the event append — a refused event leaves zero trace.

_gate_json() { # file schema label
  [ -f "$1" ] || die "$EX_ARTIFACT" "gate: $3 required (missing $1)"
  json_valid "$1" || die "$EX_ARTIFACT" "gate: $3 is not valid JSON (write JSON — it is valid YAML)"
  schema_check "$2" "$1" || die "$EX_ARTIFACT" "gate: $3 is missing required keys (see $2)"
}

_acceptance_ok() { # run-dir schemas-dir
  [ -f "$1/acceptance.yaml" ] \
    && json_valid "$1/acceptance.yaml" \
    && schema_check "$2/acceptance.schema.json" "$1/acceptance.yaml" \
    && jq -e '.checks | length > 0
              and all(.[]; has("id") and has("command") and has("expected_exit"))' \
      "$1/acceptance.yaml" >/dev/null 2>&1
}

# enforce_exit_gate <event> <run-dir> <schemas-dir> <scripts-dir>
enforce_exit_gate() {
  _eg_event=$1
  _eg_rd=$2
  _eg_sd=$3
  _eg_scripts=$4
  case $_eg_event in
    TaskClassified)
      _gate_json "$_eg_rd/problem.yaml" "$_eg_sd/problem.schema.json" "problem.yaml"
      jq -e '.keywords | length > 0' "$_eg_rd/problem.yaml" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): problem.yaml keywords[] must be non-empty"
      ;;
    SkillsSelected)
      _gate_json "$_eg_rd/selected-skills.yaml" "$_eg_sd/selected-skills.schema.json" "selected-skills.yaml"
      [ -f "$_eg_rd/candidates.json" ] \
        || die "$EX_ARTIFACT" "gate($_eg_event): candidates.json missing — run select-skills.sh first"
      jq -e --slurpfile c "$_eg_rd/candidates.json" '
        [$c[0][].name] as $names
        | (.selected | type == "array" and length >= 1 and length <= 5)
          and all(.selected[];
              (.skill as $s | ($names | index($s)) != null)
              and ((.role // "") | length > 0)
              and ((.reason // "") | length > 0))
      ' "$_eg_rd/selected-skills.yaml" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): selection must pick 1-5 skills from candidates.json, each with role and reason"
      ;;
    PlanCreated)
      _gate_json "$_eg_rd/plan.yaml" "$_eg_sd/plan.schema.json" "plan.yaml"
      "$_eg_scripts/check-plan.sh" "$_eg_rd/plan.yaml" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): plan.yaml rejected — run check-plan.sh for details"
      ;;
    TestsDefined)
      _acceptance_ok "$_eg_rd" "$_eg_sd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): acceptance.yaml must define checks[] with id, command, expected_exit"
      ;;
    BaselineRecorded)
      if ! _acceptance_ok "$_eg_rd" "$_eg_sd"; then
        jq -es 'any(.[]; .event == "TDDWaived" and ((.payload.reason // "") | length > 0))' \
          "$_eg_rd/events.jsonl" >/dev/null 2>&1 \
          || die "$EX_ARTIFACT" "gate($_eg_event): needs a valid acceptance.yaml or a TDDWaived event with a reason"
      fi
      ;;
  esac
}

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
              and all(.[]; has("id") and has("command") and (.expected_exit | type == "number"))
              and ((map(.id) | unique | length) == length)' \
      "$1/acceptance.yaml" >/dev/null 2>&1
}

# _waiver_ok <run-dir>
# A TDD waiver only counts if it was recorded AFTER the most recent entry
# into TEST_DESIGN — a waiver from an earlier plan cycle must not disable
# the acceptance gate for later cycles.
_waiver_ok() {
  jq -es '
    . as $ev
    | ([range(length) | select($ev[.].to == "TEST_DESIGN" and $ev[.].from != "TEST_DESIGN")] | max) as $entry
    | ($entry != null)
      and any(range(length); . > $entry
          and $ev[.].event == "TDDWaived"
          and (($ev[.].payload.reason // "") | length > 0))
  ' "$1/events.jsonl" >/dev/null 2>&1
}

_latest_worktree_path() { # run-dir
  jq -res '[.[] | select(.event == "WorktreePrepared")] | last | .payload.path // empty' \
    "$1/events.jsonl"
}

_has_worktree_prepared() { # run-dir
  _hwp_path=$(_latest_worktree_path "$1")
  [ -n "$_hwp_path" ] && [ -d "$_hwp_path" ]
}

_has_manual_summary() { # payload-file
  [ -n "$1" ] && [ -f "$1" ] && jq -e '((.manual_summary // "") | length > 0)' "$1" >/dev/null 2>&1
}

_has_step_completed() { # run-dir
  jq -es 'any(.[]; .event == "StepCompleted" and ((.payload.evidence // "") | length > 0))' \
    "$1/events.jsonl" >/dev/null 2>&1
}

_latest_acceptance_ok() { # run-dir acceptance-file
  jq -es --slurpfile a "$2" '
    . as $ev
    | ($a[0].checks // []) as $checks
    | all($checks[]; . as $c
        | ([ $ev[] | select(.event == "AcceptanceChecked" and .payload.check_id == $c.id) ] | last) as $latest
        | ($latest != null and ($latest.payload.actual_exit == $c.expected_exit)))
  ' "$1/events.jsonl" >/dev/null 2>&1
}

_approved_risky_evidence_ok() { # run-dir
  find "$1/evidence" -mindepth 2 -maxdepth 2 -name meta.json 2>/dev/null \
    | while IFS= read -r _are_meta; do
        jq -e '(.effective_risk == "R3" or .effective_risk == "R4")
               and ((.approval_seq // "") | tostring | length == 0)' "$_are_meta" >/dev/null 2>&1 \
          && printf '%s\n' "$_are_meta"
      done | { IFS= read -r _are_bad; [ -z "${_are_bad:-}" ]; }
}

# enforce_exit_gate <event> <run-dir> <schemas-dir> <scripts-dir> [payload-file]
enforce_exit_gate() {
  _eg_event=$1
  _eg_rd=$2
  _eg_sd=$3
  _eg_scripts=$4
  _eg_payload=${5:-}
  case $_eg_event in
    TaskClassified)
      _gate_json "$_eg_rd/problem.yaml" "$_eg_sd/problem.schema.json" "problem.yaml"
      jq -e '(.domain == "dev" or .domain == "ops") and (.keywords | length > 0)' \
        "$_eg_rd/problem.yaml" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): problem.yaml needs domain dev|ops and non-empty keywords[]"
      ;;
    SkillsSelected)
      _gate_json "$_eg_rd/selected-skills.yaml" "$_eg_sd/selected-skills.schema.json" "selected-skills.yaml"
      [ -f "$_eg_rd/candidates.json" ] \
        || die "$EX_ARTIFACT" "gate($_eg_event): candidates.json missing — run select-skills.sh first"
      jq -e --slurpfile c "$_eg_rd/candidates.json" '
        [$c[0][].name] as $names
        | (.selected | type == "array" and length >= 1 and length <= 5)
          and ((.selected | map(.skill) | unique | length) == (.selected | length))
          and all(.selected[];
              (.skill as $s | ($names | index($s)) != null)
              and ((.role // "") | length > 0)
              and ((.reason // "") | length > 0))
      ' "$_eg_rd/selected-skills.yaml" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): selection must pick 1-5 DISTINCT skills from candidates.json, each with role and reason"
      ;;
    PlanCreated)
      _gate_json "$_eg_rd/plan.yaml" "$_eg_sd/plan.schema.json" "plan.yaml"
      if ! _eg_cp_out=$("$_eg_scripts/check-plan.sh" "$_eg_rd/plan.yaml" 2>&1); then
        die "$EX_ARTIFACT" "gate($_eg_event): plan.yaml rejected — $_eg_cp_out"
      fi
      ;;
    TestsDefined)
      _acceptance_ok "$_eg_rd" "$_eg_sd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): acceptance.yaml must define checks[] with id, command, expected_exit"
      ;;
    BaselineRecorded)
      if ! _acceptance_ok "$_eg_rd" "$_eg_sd"; then
        _waiver_ok "$_eg_rd" \
          || die "$EX_ARTIFACT" "gate($_eg_event): needs a valid acceptance.yaml or a TDDWaived event (with a reason) from THIS test-design cycle"
      fi
      ;;
    ImplementationCompleted)
      _has_worktree_prepared "$_eg_rd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): WorktreePrepared event required"
      _has_step_completed "$_eg_rd" || _has_manual_summary "$_eg_payload" \
        || die "$EX_ARTIFACT" "gate($_eg_event): needs StepCompleted evidence or payload.manual_summary"
      ;;
    ValidationCompleted)
      _acceptance_ok "$_eg_rd" "$_eg_sd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): valid acceptance.yaml required"
      _latest_acceptance_ok "$_eg_rd" "$_eg_rd/acceptance.yaml" \
        || die "$EX_ARTIFACT" "gate($_eg_event): latest AcceptanceChecked evidence must match expected_exit"
      _approved_risky_evidence_ok "$_eg_rd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): R3/R4 evidence requires approval_seq"
      ;;
  esac
}

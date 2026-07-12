# shellcheck shell=sh
# Exit gates: each planning phase owes an artifact before its exit event.
# Called by record-event.sh under the lock, after transition resolution,
# before the event append — a refused event leaves zero trace.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/evidence.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/scope.sh"

_gate_json() { # file schema label
  [ -f "$1" ] || die "$EX_ARTIFACT" "gate: $3 required (missing $1)"
  json_valid "$1" || die "$EX_ARTIFACT" "gate: $3 is not valid JSON (write JSON — it is valid YAML)"
  schema_check "$2" "$1" || die "$EX_ARTIFACT" "gate: $3 is missing required keys (see $2)"
}

# _interview_mode <run-dir> — prints ask|auto, empty for pre-interview runs.
_interview_mode() {
  jq -r '.interview.mode // empty' "$1/state.json"
}

# _questions_all_answered <run-dir> — 0 when every question carries a
# non-empty answer and a recorded answerer.
_questions_all_answered() {
  jq -e 'all(.questions[]; ((.answer // "") | length > 0)
         and (.answered_by == "human" or .answered_by == "agent"))' \
    "$1/questions.yaml" >/dev/null 2>&1
}

# _questions_shape_ok <run-dir> <schemas-dir> — structural rules shared by
# all three interview gates: 1-5 questions, unique non-empty ids,
# non-empty question and why_it_matters.
_questions_shape_ok() {
  _qs_f=$1/questions.yaml
  _gate_json "$_qs_f" "$2/questions.schema.json" "questions.yaml"
  jq -e '(.questions | type == "array" and length >= 1 and length <= 5)
         and ((.questions | map(.id) | unique | length) == (.questions | length))
         and all(.questions[]; ((.id // "") | length > 0)
             and ((.question // "") | length > 0)
             and ((.why_it_matters // "") | length > 0))' \
    "$_qs_f" >/dev/null 2>&1 \
    || die "$EX_ARTIFACT" "gate: questions.yaml needs 1-5 questions with unique ids, question, why_it_matters"
}

# _verdict_payload_ok <event> <verdict-word> <schemas-dir> <payload-file>
# Shared contract for all four oracle verdict events: schema-valid payload,
# verdict word matching the event, numeric score categories, criteria[]
# entries with criterion text and a boolean met, non-empty reason.
_verdict_payload_ok() {
  { [ -n "$4" ] && [ -f "$4" ]; } \
    || die "$EX_ARTIFACT" "gate($1): verdict payload required (see schemas/oracle.schema.json)"
  _gate_json "$4" "$3/oracle.schema.json" "oracle verdict payload"
  jq -e --arg v "$2" '
    .verdict == $v
    and ((.reason // "") | length > 0)
    and ([.score.acceptance_criteria, .score.automated_tests,
          .score.specialist_validation, .score.adversarial_review,
          .score.scope_discipline, .score.safety_compliance, .score.total]
         | all(type == "number"))
    and (.criteria | type == "array")
    and all(.criteria[]; ((.criterion // "") | length > 0) and (.met | type == "boolean"))
  ' "$4" >/dev/null 2>&1 \
    || die "$EX_ARTIFACT" "gate($1): payload needs verdict \"$2\", numeric score categories, criteria[] with criterion+met, and a reason"
}

# _oracle_approval_ok <run-dir> <schemas-dir> <scripts-dir> <payload>
# The kernel re-checks every mechanical hard blocker itself: a verdict that
# claims "approved" past a failed check is refused regardless of its score.
_oracle_approval_ok() {
  jq -e '.score.total >= 90' "$4" >/dev/null 2>&1 \
    || die "$EX_ARTIFACT" "gate(OracleApproved): score.total must be >= 90"
  jq -e 'all(.criteria[]; .met == true and ((.evidence // "") | length > 0))' \
    "$4" >/dev/null 2>&1 \
    || die "$EX_ARTIFACT" "gate(OracleApproved): every criterion needs met=true and an evidence pointer"
  jq -e --slurpfile p "$1/problem.yaml" '
    [.criteria[].criterion] as $covered
    | all($p[0].acceptance_criteria[]?; . as $c | ($covered | index($c)) != null)
  ' "$4" >/dev/null 2>&1 \
    || die "$EX_ARTIFACT" "gate(OracleApproved): criteria[] must cover every problem.yaml acceptance_criteria entry"
  _acceptance_ok "$1" "$2" \
    || die "$EX_ARTIFACT" "gate(OracleApproved): blocker — acceptance.yaml invalid"
  _latest_acceptance_ok "$1" "$2" "$1/acceptance.yaml" \
    || die "$EX_ARTIFACT" "gate(OracleApproved): blocker — a required check lacks passing current-cycle evidence"
  _approved_risky_evidence_ok "$1" \
    || die "$EX_ARTIFACT" "gate(OracleApproved): blocker — R3/R4 evidence without approval"
  "$3/validate-artifacts.sh" "$1" >/dev/null 2>&1 \
    || die "$EX_ARTIFACT" "gate(OracleApproved): blocker — validate-artifacts failed"
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

_step_requires_diff() { # evidence-meta
  jq -e '(.declared_risk != "R0" or .effective_risk != "R0")
          and (((.diff_sha256 // "") | length) == 0)' "$1" >/dev/null 2>&1
}

_step_evidence_ok() { # run-dir schemas-dir step-id
  _seo_evidence=$(jq -res --arg id "$3" '
    [.[] | select(.event == "StepCompleted" and .payload.step_id == $id)] | last | .payload.evidence // empty
  ' "$1/events.jsonl" || true)
  [ -n "$_seo_evidence" ] || return 1
  evidence_valid "$2" "$1" "$_seo_evidence" step "$3" 0 false || return 1
  _seo_meta=$_seo_evidence/meta.json
  # Evidence must be for the step's CURRENT command: replacing a step's
  # command in plan.yaml invalidates evidence captured for the old one.
  _seo_cmd=$(jq -r --arg id "$3" '[.steps[] | select(.id == $id)] | last | .command // ""' "$1/plan.yaml")
  jq -e --arg cmd "$_seo_cmd" '.command == $cmd' "$_seo_meta" >/dev/null 2>&1 || return 1
  _step_requires_diff "$_seo_meta" && return 1
  return 0
}

# Ids come from jq one per line; while-read (not an unquoted for) so ids
# containing spaces or glob characters cannot split or expand.
_has_step_completed() { # run-dir schemas-dir
  [ -f "$1/plan.yaml" ] || return 1
  _hsc_steps=$(jq -r '.steps[] | select(((.command // "") | length) > 0) | .id' "$1/plan.yaml")
  [ -n "$_hsc_steps" ] || return 1
  while IFS= read -r _hsc_step; do
    [ -n "$_hsc_step" ] || continue
    _step_evidence_ok "$1" "$2" "$_hsc_step" || return 1
  done <<EOF
$_hsc_steps
EOF
  return 0
}

_latest_acceptance_ok() { # run-dir schemas-dir acceptance-file
  _lao_checks=$(jq -r '.checks[].id' "$3")
  [ -n "$_lao_checks" ] || return 1
  while IFS= read -r _lao_id; do
    [ -n "$_lao_id" ] || continue
    _lao_expected=$(jq -r --arg id "$_lao_id" '[.checks[] | select(.id == $id)] | last | .expected_exit' "$3")
    _lao_cmd=$(jq -r --arg id "$_lao_id" '[.checks[] | select(.id == $id)] | last | .command // ""' "$3")
    # Only evidence from the CURRENT validating cycle counts: a check result
    # captured before the latest entry into VALIDATING predates the code
    # under validation (same recency rule as _waiver_ok).
    _lao_payload=$(jq -cres --arg id "$_lao_id" '
      . as $ev
      | ([range(length) | select($ev[.].to == "VALIDATING" and $ev[.].from != "VALIDATING")] | max) as $entry
      | if $entry == null then empty
        else ([range(length) | select(. > $entry) | $ev[.]
               | select(.event == "AcceptanceChecked" and .payload.check_id == $id)]
              | last | .payload // empty)
        end
    ' "$1/events.jsonl" || true)
    [ -n "$_lao_payload" ] || return 1
    _lao_actual=$(printf '%s\n' "$_lao_payload" | jq -r '.actual_exit // empty')
    _lao_event_expected=$(printf '%s\n' "$_lao_payload" | jq -r '.expected_exit // empty')
    _lao_evidence=$(printf '%s\n' "$_lao_payload" | jq -r '.evidence // empty')
    [ "$_lao_actual" = "$_lao_expected" ] || return 1
    [ "$_lao_event_expected" = "$_lao_expected" ] || return 1
    evidence_valid "$2" "$1" "$_lao_evidence" acceptance "$_lao_id" "$_lao_expected" false || return 1
    jq -e --arg cmd "$_lao_cmd" '.command == $cmd' "$_lao_evidence/meta.json" >/dev/null 2>&1 || return 1
  done <<EOF
$_lao_checks
EOF
  return 0
}

_approved_risky_evidence_ok() { # run-dir
  find "$1/evidence" -mindepth 2 -maxdepth 2 -name meta.json 2>/dev/null \
    | while IFS= read -r _are_meta; do
      jq -e '(.effective_risk == "R3" or .effective_risk == "R4")
               and ((.approval_seq // "") | tostring | length == 0)' "$_are_meta" >/dev/null 2>&1 \
        && printf '%s\n' "$_are_meta"
    done | {
    IFS= read -r _are_bad
    [ -z "${_are_bad:-}" ]
  }
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
    ApprovalGranted)
      _gate_json "$_eg_payload" "$_eg_sd/approval.schema.json" "ApprovalGranted payload"
      _eg_kind=$(jq -r '.kind // empty' "$_eg_payload")
      _eg_rt=$(jq -r '.approval.return_to // empty' "$_eg_rd/state.json")
      case $_eg_kind in
        command)
          # A JUDGING wait was raised by OracleNeedsHuman: only a human
          # continuation may resolve it — a command approval here would also
          # pre-authorize that command for later execution.
          [ "$_eg_rt" != "JUDGING" ] \
            || die "$EX_ARTIFACT" "gate($_eg_event): this wait resolves an OracleNeedsHuman judgment; use kind \"continuation\""
          jq -e '((.step_id // "") | length > 0)
                 and ((.command // "") | length > 0)
                 and (.effective_risk == "R3" or .effective_risk == "R4")
                 and ((.approver // "") | length > 0)
                 and ((.approved_at // "") | length > 0)' \
            "$_eg_payload" >/dev/null 2>&1 \
            || die "$EX_ARTIFACT" "gate($_eg_event): command approval needs step_id, command, effective_risk R3|R4, approver, approved_at"
          ;;
        continuation)
          [ "$_eg_rt" = "JUDGING" ] \
            || die "$EX_ARTIFACT" "gate($_eg_event): continuation approvals only resolve an OracleNeedsHuman wait (return_to: ${_eg_rt:-unset}); use kind \"command\""
          jq -e '((.approver // "") | length > 0)
                 and ((.approved_at // "") | length > 0)
                 and ((.note // "") | length > 0)' \
            "$_eg_payload" >/dev/null 2>&1 \
            || die "$EX_ARTIFACT" "gate($_eg_event): continuation approval needs approver, approved_at, note"
          ;;
        *)
          die "$EX_ARTIFACT" "gate($_eg_event): payload needs kind \"command\" or \"continuation\""
          ;;
      esac
      ;;
    WorktreePrepared)
      { [ -n "$_eg_payload" ] && [ -f "$_eg_payload" ]; } \
        || die "$EX_ARTIFACT" "gate($_eg_event): payload with path and base_revision required — use opsman worktree"
      jq -e '((.path // "") | length > 0) and ((.base_revision // "") | length > 0)' \
        "$_eg_payload" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): payload needs non-empty path and base_revision"
      _eg_wt=$(jq -r '.path' "$_eg_payload")
      [ -d "$_eg_wt" ] \
        || die "$EX_ARTIFACT" "gate($_eg_event): worktree path does not exist: $_eg_wt"
      ;;
    StepCompleted)
      { [ -n "$_eg_payload" ] && [ -f "$_eg_payload" ]; } \
        || die "$EX_ARTIFACT" "gate($_eg_event): payload with step_id and evidence required — use opsman run-step"
      _eg_sc_id=$(jq -r '.step_id // empty' "$_eg_payload")
      _eg_sc_ev=$(jq -r '.evidence // empty' "$_eg_payload")
      { [ -n "$_eg_sc_id" ] && [ -n "$_eg_sc_ev" ]; } \
        || die "$EX_ARTIFACT" "gate($_eg_event): payload needs step_id and evidence"
      evidence_valid "$_eg_sd" "$_eg_rd" "$_eg_sc_ev" step "$_eg_sc_id" 0 false \
        || die "$EX_ARTIFACT" "gate($_eg_event): evidence invalid for step $_eg_sc_id: $_eg_sc_ev"
      ;;
    AcceptanceChecked)
      { [ -n "$_eg_payload" ] && [ -f "$_eg_payload" ]; } \
        || die "$EX_ARTIFACT" "gate($_eg_event): payload with check_id and evidence required — use opsman validate"
      jq -e '((.check_id // "") | length > 0) and ((.evidence // "") | length > 0)
             and (.actual_exit | type == "number") and (.expected_exit | type == "number")' \
        "$_eg_payload" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): payload needs check_id, evidence, numeric actual_exit/expected_exit"
      _eg_ac_id=$(jq -r '.check_id' "$_eg_payload")
      _eg_ac_ev=$(jq -r '.evidence' "$_eg_payload")
      _eg_ac_actual=$(jq -r '.actual_exit' "$_eg_payload")
      evidence_valid "$_eg_sd" "$_eg_rd" "$_eg_ac_ev" acceptance "$_eg_ac_id" "$_eg_ac_actual" false \
        || die "$EX_ARTIFACT" "gate($_eg_event): evidence invalid for check $_eg_ac_id: $_eg_ac_ev"
      ;;
    ImplementationCompleted)
      _has_worktree_prepared "$_eg_rd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): WorktreePrepared event required"
      _has_step_completed "$_eg_rd" "$_eg_sd" || _has_manual_summary "$_eg_payload" \
        || die "$EX_ARTIFACT" "gate($_eg_event): needs StepCompleted evidence or payload.manual_summary"
      # A scoped plan may not leave IMPLEMENTING with out-of-scope changes:
      # this is the hard stop that also covers manual agent edits.
      _eg_ic_wt=$(_latest_worktree_path "$_eg_rd")
      _eg_ic_viol=$(scope_violations "$_eg_ic_wt" "$_eg_rd/plan.yaml") \
        || die "$EX_ARTIFACT" "gate($_eg_event): scope check failed — worktree unreadable: $_eg_ic_wt"
      [ -z "$_eg_ic_viol" ] \
        || die "$EX_ARTIFACT" "gate($_eg_event): changes outside plan allowed_files scope: $(printf '%s' "$_eg_ic_viol" | tr '\n' ' ')"
      ;;
    ValidationCompleted)
      _acceptance_ok "$_eg_rd" "$_eg_sd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): valid acceptance.yaml required"
      _latest_acceptance_ok "$_eg_rd" "$_eg_sd" "$_eg_rd/acceptance.yaml" \
        || die "$EX_ARTIFACT" "gate($_eg_event): latest AcceptanceChecked evidence must match expected_exit"
      _approved_risky_evidence_ok "$_eg_rd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): R3/R4 evidence requires approval_seq"
      ;;
    HypothesisFormed)
      { [ -n "$_eg_payload" ] && [ -f "$_eg_payload" ]; } \
        || die "$EX_ARTIFACT" "gate($_eg_event): payload with hypothesis_id and statement required"
      jq -e '((.hypothesis_id // "") | length > 0) and ((.statement // "") | length > 0)' \
        "$_eg_payload" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): payload needs non-empty hypothesis_id and statement"
      ;;
    OracleApproved)
      _verdict_payload_ok "$_eg_event" approved "$_eg_sd" "$_eg_payload"
      _oracle_approval_ok "$_eg_rd" "$_eg_sd" "$_eg_scripts" "$_eg_payload"
      ;;
    OracleRejected)
      _verdict_payload_ok "$_eg_event" rejected "$_eg_sd" "$_eg_payload"
      ;;
    OracleInconclusive)
      _verdict_payload_ok "$_eg_event" inconclusive "$_eg_sd" "$_eg_payload"
      ;;
    OracleNeedsHuman)
      _verdict_payload_ok "$_eg_event" needs_human "$_eg_sd" "$_eg_payload"
      ;;
    QuestionsAsked)
      _questions_shape_ok "$_eg_rd" "$_eg_sd"
      jq -e 'any(.questions[]; ((.answer // "") | length == 0))' \
        "$_eg_rd/questions.yaml" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): at least one question must be unanswered — nothing to ask otherwise"
      ;;
    AnswersProvided)
      _questions_shape_ok "$_eg_rd" "$_eg_sd"
      _questions_all_answered "$_eg_rd" \
        || die "$EX_ARTIFACT" "gate($_eg_event): every question needs a non-empty answer and answered_by"
      ;;
    QuestionsSelfAnswered)
      [ "$(_interview_mode "$_eg_rd")" = "auto" ] \
        || die "$EX_ARTIFACT" "gate($_eg_event): only legal in --no-q (auto) runs — ask the human via QuestionsAsked"
      _questions_shape_ok "$_eg_rd" "$_eg_sd"
      jq -e 'all(.questions[]; ((.answer // "") | length > 0) and .answered_by == "agent")' \
        "$_eg_rd/questions.yaml" >/dev/null 2>&1 \
        || die "$EX_ARTIFACT" "gate($_eg_event): every question needs an agent-authored answer (answered_by: agent)"
      ;;
  esac
}

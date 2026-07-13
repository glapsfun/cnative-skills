# Opsman State Machine

The transition table ships as data in `scripts/state-machine.tsv`
(`current-state <TAB> event <TAB> next-state`). `*` in the state column
matches any state. `@return` as a next-state resolves via `state.json .approval.return_to` when leaving `WAITING_APPROVAL` (set on entry) and via `state.json .input.return_to` when leaving `WAITING_INPUT` (set on entry).

## States

`DISCOVERING`, `UNDERSTANDING`, `SELECTING`, `PLANNING`, `TEST_DESIGN`,
`IMPLEMENTING`, `VALIDATING`, `DIAGNOSING`, `REPLANNING`, `JUDGING`,
`WAITING_APPROVAL`, `WAITING_INPUT`, `BLOCKED`, `COMPLETED`, `ABANDONED`.

## Transitions

| From | Event | To |
| --- | --- | --- |
| DISCOVERING | SkillsIndexed | UNDERSTANDING |
| UNDERSTANDING | TaskClassified | SELECTING |
| UNDERSTANDING | QuestionsSelfAnswered | UNDERSTANDING |
| SELECTING | SkillsSelected | PLANNING |
| PLANNING | PlanCreated | TEST_DESIGN |
| REPLANNING | PlanCreated | TEST_DESIGN |
| TEST_DESIGN | TestsDefined | TEST_DESIGN |
| TEST_DESIGN | TDDWaived | TEST_DESIGN |
| TEST_DESIGN | BaselineRecorded | IMPLEMENTING |
| IMPLEMENTING | WorktreePrepared | IMPLEMENTING |
| IMPLEMENTING | StepCompleted | IMPLEMENTING |
| IMPLEMENTING | ImplementationCompleted | VALIDATING |
| VALIDATING | AcceptanceChecked | VALIDATING |
| VALIDATING | TestFailed | DIAGNOSING |
| VALIDATING | ValidationCompleted | JUDGING |
| DIAGNOSING | HypothesisFormed | IMPLEMENTING |
| DIAGNOSING | ReplanRequested | REPLANNING |
| JUDGING | OracleApproved | COMPLETED |
| JUDGING | OracleRejected | REPLANNING |
| JUDGING | OracleInconclusive | VALIDATING |
| JUDGING | OracleNeedsHuman | WAITING_APPROVAL |
| WAITING_APPROVAL | ApprovalGranted | @return |
| WAITING_INPUT | AnswersProvided | @return |
| * | HumanApprovalRequired | WAITING_APPROVAL |
| * | QuestionsAsked | WAITING_INPUT |
| * | BudgetExceeded | BLOCKED |
| * | RunBlocked | BLOCKED |
| * | RunAbandoned | ABANDONED |

`RunStarted` is not in the table: `init-run.sh` writes it as event seq 1
with `from: null, to: DISCOVERING`.

Terminal states: `COMPLETED`, `ABANDONED`. They match **no** table row —
wildcard rows are explicitly excluded for them, so a finished run accepts
no further events. `BLOCKED` is not terminal: it requires human
intervention, and `RunAbandoned` remains legal there.

## Exit gates

Some transitions are additionally gated on artifacts; `opsman record`
refuses them with exit 5 (zero trace) until the artifact validates:

| Event | Requires |
| --- | --- |
| QuestionsAsked | `questions.yaml` — 1-5 unique-id questions, at least one unanswered |
| AnswersProvided | every question in `questions.yaml` answered by a human (non-empty answer, `answered_by: "human"`) |
| QuestionsSelfAnswered | interview mode `auto`; every question answered with `answered_by: "agent"` |
| TaskClassified | `problem.yaml` (domain dev\|ops, non-empty keywords) **plus** the journaled interview: ask mode needs an `AnswersProvided` event, auto mode a `QuestionsSelfAnswered` event; pre-interview runs exempt |
| SkillsSelected | `selected-skills.yaml` — 1–5 distinct skills from `candidates.json`, each with role and reason |
| PlanCreated | `plan.yaml` passing check-plan.sh (unique ids, resolvable deps, acyclic, risk R0–R4) |
| TestsDefined | `acceptance.yaml` — checks with id, command, numeric expected_exit, unique ids |
| BaselineRecorded | valid `acceptance.yaml` **or** a `TDDWaived` event (with reason) from the current TEST_DESIGN cycle |
| WorktreePrepared | payload `path` (existing directory), `base_revision`, and `mode` matching the run's workspace mode (branch mode also requires payload `branch` matching `workspace.branch`) — use `opsman workspace` |
| StepCompleted | payload `step_id` and `evidence` pointing at a valid exit-0 evidence directory — use `opsman run-step` |
| AcceptanceChecked | payload `check_id`, `evidence`, numeric `actual_exit`/`expected_exit`; evidence matches `actual_exit` — use `opsman validate` |
| ImplementationCompleted | latest `WorktreePrepared` plus valid `StepCompleted` evidence (matching each step's current command) for command-backed steps or payload `manual_summary`; branch mode: checkout still on the run branch; current mode: HEAD still at base and no baselined file modified |
| ValidationCompleted | valid `acceptance.yaml`; per check, a valid `AcceptanceChecked` evidence from the current VALIDATING cycle matching `expected_exit` and the check's current command; R3/R4 evidence has approval |
| HypothesisFormed | payload `hypothesis_id` and `statement`; refused with exit 6 over per-hypothesis attempts or when the last two TestFailed cycles produced identical evidence |
| OracleRejected / OracleInconclusive / OracleNeedsHuman | verdict payload (schemas/oracle.schema.json) with matching `verdict` and non-empty reason |
| OracleApproved | verdict payload as above; score.total >= 90; every criterion met with evidence, covering problem.yaml acceptance_criteria; kernel re-checks acceptance evidence, R3/R4 approvals, and validate-artifacts |
| ApprovalGranted | kind `command` (step_id, command, effective_risk R3\|R4, approver, approved_at) or kind `continuation` (approver, approved_at, note; only while return_to is JUDGING) |

Approval bookkeeping is keyed on the **destination state**, not the event
name: any transition entering `WAITING_APPROVAL` from another state
records `approval.return_to`; re-entries never clobber it; resolving
`@return` clears it. Transitions entering `WAITING_INPUT` record `input.return_to` with identical semantics (set on entry, never clobbered by re-entry, cleared when `@return` resolves); the two fields are independent.
`validate-artifacts.sh` replays the whole log against
this table, so state is always rebuildable by replaying `events.jsonl`.

Budgets are enforced in the same transaction (exit 6, zero trace): entries
into IMPLEMENTING from TEST_DESIGN/DIAGNOSING count against
`max_iterations`; `HypothesisFormed` is bounded per hypothesis and by the
no-new-evidence rule; `collect-evidence.sh` bounds total commands; and
`ImplementationCompleted` bounds changed files. Terminal transitions
(COMPLETED, BLOCKED, ABANDONED) automatically write `result.md` and
`final.patch` via `finalize.sh`.

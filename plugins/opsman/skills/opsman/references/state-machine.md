# Opsman State Machine

The transition table ships as data in `scripts/state-machine.tsv`
(`current-state <TAB> event <TAB> next-state`). `*` in the state column
matches any state. `@return` as a next-state resolves to
`state.json .approval.return_to` (set when entering `WAITING_APPROVAL`).

## States

`DISCOVERING`, `UNDERSTANDING`, `SELECTING`, `PLANNING`, `TEST_DESIGN`,
`IMPLEMENTING`, `VALIDATING`, `DIAGNOSING`, `REPLANNING`, `JUDGING`,
`WAITING_APPROVAL`, `BLOCKED`, `COMPLETED`, `ABANDONED`.

## Transitions

| From | Event | To |
| --- | --- | --- |
| DISCOVERING | SkillsIndexed | UNDERSTANDING |
| UNDERSTANDING | TaskClassified | SELECTING |
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
| * | HumanApprovalRequired | WAITING_APPROVAL |
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
| TaskClassified | `problem.yaml` (domain dev\|ops, non-empty keywords) |
| SkillsSelected | `selected-skills.yaml` — 1–5 distinct skills from `candidates.json`, each with role and reason |
| PlanCreated | `plan.yaml` passing check-plan.sh (unique ids, resolvable deps, acyclic, risk R0–R4) |
| TestsDefined | `acceptance.yaml` — checks with id, command, numeric expected_exit, unique ids |
| BaselineRecorded | valid `acceptance.yaml` **or** a `TDDWaived` event (with reason) from the current TEST_DESIGN cycle |
| WorktreePrepared | payload `path` (existing directory) and `base_revision` — use `opsman worktree` |
| StepCompleted | payload `step_id` and `evidence` pointing at a valid exit-0 evidence directory — use `opsman run-step` |
| AcceptanceChecked | payload `check_id`, `evidence`, numeric `actual_exit`/`expected_exit`; evidence matches `actual_exit` — use `opsman validate` |
| ImplementationCompleted | latest `WorktreePrepared` plus valid `StepCompleted` evidence (matching each step's current command) for command-backed steps or payload `manual_summary` |
| ValidationCompleted | valid `acceptance.yaml`; per check, a valid `AcceptanceChecked` evidence from the current VALIDATING cycle matching `expected_exit` and the check's current command; R3/R4 evidence has approval |

Approval bookkeeping is keyed on the **destination state**, not the event
name: any transition entering `WAITING_APPROVAL` from another state
records `approval.return_to`; re-entries never clobber it; resolving
`@return` clears it. `validate-artifacts.sh` replays the whole log against
this table, so state is always rebuildable by replaying `events.jsonl`.

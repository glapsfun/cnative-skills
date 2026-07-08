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
| IMPLEMENTING | ImplementationCompleted | VALIDATING |
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

Terminal states: `COMPLETED`, `ABANDONED`. `BLOCKED` requires human
intervention. State is always rebuildable by replaying `events.jsonl`.

---
name: opsman
description: "Local-first meta-agent orchestrator for Dev and Ops tasks. Use when the user asks to run opsman, orchestrate a multi-skill task, check opsman status, or wants a test-driven, evidence-gated execution loop that discovers local skills, selects a team, plans, implements, and validates command evidence. Triggers: opsman, orchestrate, meta-agent, orchestrator, run lifecycle, evidence-gated validation, capability map, skill registry."
---

# Opsman — Meta-Agent Orchestrator

Opsman converts a Dev or Ops request into a persistent, test-driven execution
loop using repository-local skills and POSIX automation. Agents reason; the
shell proves. All run state lives in the target repository under `.opsman/`
(gitignored), so a run started in Claude Code can be resumed in Codex.

## The one rule

**Interact with run state ONLY through the `opsman` kernel.** Never edit
files under `.opsman/` by hand, and never skip recording an event. If you
did work, `opsman record` it — unrecorded work does not exist.

The kernel lives at `scripts/opsman` inside this skill. Call it with the
skill's absolute path, e.g. `<skill-dir>/scripts/opsman status`.

## Kernel verbs

| Verb | Purpose |
| --- | --- |
| `opsman start [--limit key=value ...] [--] "<task>"` | Build the skill registry, initialize a run (state `DISCOVERING`) |
| `opsman next` | Render the context packet for the role that owns the current state |
| `opsman worktree [<run-id>]` | Create or verify the isolated run worktree |
| `opsman run-step <step-id>` | Execute one command-backed plan step under policy |
| `opsman validate` | Run acceptance checks and capture evidence |
| `opsman status` | Print the current run's `STATE.md` |
| `opsman record --event <Event> [--payload <file.json>]` | The only way to change state |
| `opsman map` | Rebuild `.opsman/registry/` from discovered skills |
| `opsman validate-run [<run-id>]` | Check run artifacts for consistency |
| `opsman judge` | Validate artifacts, then render the oracle packet (JUDGING only) |
| `opsman resume [<run-id>]` | Rebuild state from the journal, validate, reattach; repoints `.opsman/current` when given a run-id |
| `opsman clean [--yes]` | List (default) or delete finished runs and orphan worktrees |

The UNDERSTANDING→JUDGING phases enforce artifact and evidence gates:
`opsman record` refuses phase-exit events until the required planning
artifact, worktree, implementation evidence, or acceptance evidence exists
and validates.

### Judging and recovery (M4)

From JUDGING, run `opsman judge` — it validates run artifacts and prints the
oracle packet. Record exactly one verdict with a payload
(`schemas/oracle.schema.json`): `OracleApproved` (kernel re-checks the
mechanical blockers and refuses approval past a failed check),
`OracleRejected` (→ REPLANNING), `OracleInconclusive` (→ VALIDATING; checks
must be re-run), or `OracleNeedsHuman` (→ WAITING_APPROVAL; the human reply
is recorded as `ApprovalGranted` with `kind: "continuation"`).

From DIAGNOSING, record `HypothesisFormed` with `{"hypothesis_id": "...",
"statement": "..."}`. Exit 6 means a budget refused the event — the message
names the limit and the legal way out (`ReplanRequested`, `BudgetExceeded`,
or `RunAbandoned`). Budgets live in the run's `limits.json`, settable only
at `opsman start --limit key=value`.

Terminal transitions write `result.md` and `final.patch` automatically —
the patch is the deliverable; opsman never pushes.

### Resuming and cleaning (M5)

`opsman resume [<run-id>]` is the only mechanical way to reattach to a run —
after a crash, a new session, or a Claude ↔ Codex switch. It quarantines a
torn journal tail to `events.jsonl.rej`, rebuilds state from the journal,
validates artifacts (exit 5 stops the resume and leaves `.opsman/current`
untouched), repoints `.opsman/current` when given a run-id, and prints the
handoff plus the current role packet. Never re-plan work the journal
already records.

`opsman clean` lists finished runs (COMPLETED or ABANDONED) and orphan
worktrees; it deletes nothing. Show the list to the user and, on their
go-ahead, run `opsman clean --yes` to remove them. BLOCKED and in-flight
runs are never touched.

## Lifecycle

States: `DISCOVERING → UNDERSTANDING → SELECTING → PLANNING → TEST_DESIGN →
IMPLEMENTING → VALIDATING → JUDGING → COMPLETED`, with `DIAGNOSING`,
`REPLANNING`, `WAITING_APPROVAL`, `BLOCKED`, `ABANDONED` on the side. The
transition table is `scripts/state-machine.tsv`; an illegal event exits 3
and lists the legal events for the current state. See
`references/state-machine.md`.

## Failure handling

- Exit 3: you sent an event the current state does not allow — read the
  error, it lists legal events.
- Exit 4: another opsman process holds the lock; do not delete
  `.opsman/lock` unless the reported pid is dead.
- Exit 5: artifacts are inconsistent — run `opsman validate-run` and report
  findings to the user instead of hand-editing state.
- Exit 6: a budget refused the event — the message names the limit and the
  legal next event (`ReplanRequested`, `BudgetExceeded`, `RunAbandoned`).
- Exit 7: a required tool (`jq`, `git`) is missing — tell the user.

See `references/artifact-contract.md` for the full file and exit-code
contract, and `references/safety-policy.md` for risk classes R0–R4.

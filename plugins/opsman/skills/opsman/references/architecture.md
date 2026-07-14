# Opsman Architecture

Opsman follows an Elm-inspired loop:

- **Model** — persistent run state: `.opsman/runs/<run-id>/state.json`,
  derived from the append-only `events.jsonl`.
- **Message** — a typed event (`SkillsIndexed`, `PlanCreated`, `TestFailed`, …).
- **Update** — `record-event.sh`: deterministic transition via
  `state-machine.tsv`, executed under a lock, written atomically.
- **View** — rendered context packets per role (milestone 2).
- **Command** — shell actions and delegated agent work, always evidence-backed.

## Division of labor

Agents interpret intent, select skills, plan, implement, review. POSIX
scripts own discovery, registry generation, state transitions, evidence
capture, test execution, and artifact validation. A conclusion without an
evidence artifact is an opinion.

## Control plane vs execution plane

The target repository's `.opsman/` directory is the control plane
(registry, runs, lock). Implementation work happens in a dedicated
worktree `.opsman/worktrees/<run-id>/`, created and verified by the execution
lane. `.opsman/` is gitignored; portability means "same working tree, any
compatible agent".

## Roles (milestones 2+)

Discoverer, Analyst, Selector, Planner, Implementer, Verifier, Critic,
Oracle. Roles are prompt packets plus disk state — real subagents when the
harness supports them, sequential role-play otherwise. The Oracle is
read-only and judges evidence against acceptance criteria; the kernel
independently re-checks mechanical hard blockers.

## Budgets and terminal artifacts (milestone 4)

Every run carries `limits.json`; `record-event.sh` enforces iteration,
hypothesis-attempt, and no-new-evidence budgets in the same locked
transaction as the gates (exit 6, zero trace), and `collect-evidence.sh`
bounds total executed commands. Transitions into COMPLETED, BLOCKED, or
ABANDONED write `result.md` and `final.patch` mechanically via
`finalize.sh` — the patch is the deliverable; opsman never pushes.
`opsman deliver` can land that patch mechanically: a commit on a new local
branch (default `opsman/<run-id>`) planted at the run's pinned base
revision via a scratch worktree under `.opsman/worktrees/`. That branch is
the one artifact opsman creates outside `.opsman/`; pushing remains the
human's move.

## Cross-tool adapters (milestone 5)

`opsman resume` reattaches any compatible agent to a run: torn journal
tails are quarantined to `events.jsonl.rej`, state is rebuilt from the
journal, and the handoff plus current role packet are reprinted — no step
depends on conversation memory. `opsman clean` (dry run by default,
`--yes` to delete) retires finished runs and orphan worktrees. Claude Code
enters through the `/opsman`, `/opsman-resume`, `/opsman-status`, and
`/opsman-validate` commands; Codex enters through the skill interface in
`agents/openai.yaml`. All adapters defer to SKILL.md — the single protocol
source. This closes the v1 milestone plan.

## Write scope and the live board (milestone 6)

A scoped plan declares its blast radius: the union of every step's
`allowed_files` globs. `run-step` fails a straying step, and the
`ImplementationCompleted` gate refuses to leave IMPLEMENTING while any
dirty worktree file falls outside the union — the first mechanical input
behind the oracle's scope_discipline score. `opsman board` serves a
read-only loopback hub (python3 stdlib, GET-only) over `.opsman/runs` for
humans watching a run; no agent workflow depends on it.

## Interview and workspace modes (milestone 7)

`WAITING_INPUT` makes "ask the human" a journaled, resumable step: the
analyst (or any role) writes `questions.yaml` and parks via
`QuestionsAsked`; `AnswersProvided` returns to `input.return_to`.
`--no-q` runs journal self-answered questions (`QuestionsSelfAnswered`)
instead of parking — assumptions become auditable artifacts either way,
and `TaskClassified` is gated on the interview.

`--base branch|current|worktree` (required at start) selects the
execution plane: the classic isolated worktree, a fresh `opsman/<run-id>`
branch in the real checkout (deliver commits there), or the current
branch in place — where a `baseline-dirty.tsv` snapshot fences the
human's pre-existing changes out of scope checks, budgets, and
`final.patch`, and any run edit to a baselined file is refused.

## Parallel step execution (milestone 8)

`IMPLEMENTING` no longer requires walking `plan.yaml`'s `depends_on` DAG
one step at a time. `opsman ready-steps` computes the parallel-eligible
batch (DAG-ready, command-backed, `allowed_files` declared, risk R0-R2);
`opsman step-run` executes one step in a disposable scratch worktree —
content-synced to the live main worktree via a throwaway git index, never
a plain file copy — so N of them can run concurrently with no state
mutation. `opsman step-land` merges exactly one step's own marginal
change (isolated via a pre/post content-hash snapshot diff) back into the
main worktree and records `StepCompleted` through the unmodified
`record-event.sh` path, one call at a time. The state machine, gates, and
event schemas are untouched by this milestone.

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
worktree `.opsman/worktrees/<run-id>/` (milestone 3). `.opsman/` is
gitignored; portability means "same working tree, any compatible agent".

## Roles (milestones 2+)

Discoverer, Analyst, Selector, Planner, Implementer, Verifier, Critic,
Oracle. Roles are prompt packets plus disk state — real subagents when the
harness supports them, sequential role-play otherwise. The Oracle is
read-only and judges evidence against acceptance criteria; the kernel
independently re-checks mechanical hard blockers.

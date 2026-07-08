---
name: opsman
description: "Local-first meta-agent orchestrator for Dev and Ops tasks. Use when the user asks to run opsman, orchestrate a multi-skill task, resume/continue an opsman run, check opsman status, or wants a test-driven, evidence-gated execution loop that discovers local skills, selects a team, plans, implements, validates, and asks an independent Oracle to judge completion. Triggers: opsman, orchestrate, meta-agent, orchestrator, run lifecycle, oracle verdict, resume run, capability map, skill registry."
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

## Kernel verbs (milestone 1)

| Verb | Purpose |
| --- | --- |
| `opsman start "<task>"` | Build the skill registry, initialize a run (state `DISCOVERING`) |
| `opsman status` | Print the current run's `STATE.md` |
| `opsman record --event <Event> [--payload <file.json>]` | The only way to change state |
| `opsman map` | Rebuild `.opsman/registry/` from discovered skills |
| `opsman validate-run [<run-id>]` | Check run artifacts for consistency |

Verbs `next`, `validate`, `judge`, `resume`, and `clean` arrive in later
milestones; the kernel rejects them with exit 2 until then.

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
- Exit 7: a required tool (`jq`, `git`) is missing — tell the user.

See `references/artifact-contract.md` for the full file and exit-code
contract, and `references/safety-policy.md` for risk classes R0–R4.

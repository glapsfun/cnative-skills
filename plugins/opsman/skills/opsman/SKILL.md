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
| `opsman start [--global] [--limit key=value ...] [--] "<task>"` | Build the skill registry, initialize a run (state `DISCOVERING`) |
| `opsman next` | Render the context packet for the role that owns the current state |
| `opsman worktree [<run-id>]` | Create or verify the isolated run worktree |
| `opsman run-step <step-id>` | Execute one command-backed plan step under policy |
| `opsman validate` | Run acceptance checks and capture evidence |
| `opsman status` | Print the current run's `STATE.md` |
| `opsman record --event <Event> [--payload <file.json>]` | The only way to change state |
| `opsman map [--global]` | Rebuild `.opsman/registry/` from discovered skills |
| `opsman validate-run [<run-id>]` | Check run artifacts for consistency |
| `opsman judge` | Validate artifacts, then render the oracle packet (JUDGING only) |
| `opsman resume [<run-id>]` | Rebuild state from the journal, validate, reattach; repoints `.opsman/current` when given a run-id |
| `opsman clean [--yes]` | List (default) or delete finished runs and orphan worktrees |
| `opsman history [--json] [--limit <n>] [<run-id>]` | List finished runs from the append-only cross-run ledger (survives `clean`) |
| `opsman deliver [<run-id>] [--branch <name>]` | Land a COMPLETED run: commit `final.patch` on a new local branch off the pinned base, write `pr-body.md`; never pushes |
| `opsman board [--port <n>]` | Serve a read-only local hub at `127.0.0.1:41999` for humans watching runs |

The UNDERSTANDING→JUDGING phases enforce artifact and evidence gates:
`opsman record` refuses phase-exit events until the required planning
artifact, worktree, implementation evidence, or acceptance evidence exists
and validates.

### Write scope (allowed_files)

A plan step that edits files should declare `allowed_files`: glob patterns
relative to the worktree root (`*` crosses `/`, so `src/*` covers the whole
subtree). Once any step declares the field the plan is scoped: every dirty
worktree file must match the union of all declared patterns. `opsman
run-step` fails a step that strays, and `opsman record` refuses
`ImplementationCompleted` while out-of-scope changes exist. A plan with no
`allowed_files` anywhere is unscoped (legacy behavior). Never widen a
pattern just to dodge the gate — a scope mismatch means the plan is wrong.

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
after a crash, a new session, or a Claude ↔ Codex switch. It repairs the
journal tail (a torn fragment is quarantined to `events.jsonl.rej`; a
complete unterminated event is terminated in place), rebuilds state from
the journal, validates artifacts (exit 5 stops the resume and leaves
`.opsman/current` untouched), repoints `.opsman/current` when given a
run-id, and prints the handoff plus the current role packet. If `opsman
record` reports crash residue in the journal (exit 5), run `opsman resume`
to repair it. Never re-plan work the journal already records.

`opsman clean` lists finished runs (COMPLETED or ABANDONED), orphan
worktrees, and a dangling run pointer; it deletes nothing. Show the list to
the user and, on their go-ahead, run `opsman clean --yes` to remove them.
BLOCKED and in-flight runs are never touched.

### Watching a run (board)

`opsman board [--port <n>]` serves a read-only hub at
`http://127.0.0.1:41999` (or the given port) for the human: run switcher,
plan progress, acceptance results, budgets, evidence index, event tail,
and the current handoff. GET-only, loopback-only, never mutates
`.opsman/`; it is the only verb that needs `python3`. No agent workflow
may depend on it — it exists for the human watching the run.

## Lifecycle

States: `DISCOVERING → UNDERSTANDING → SELECTING → PLANNING → TEST_DESIGN →
IMPLEMENTING → VALIDATING → JUDGING → COMPLETED`, with `DIAGNOSING`,
`REPLANNING`, `WAITING_APPROVAL`, `BLOCKED`, `ABANDONED` on the side. The
transition table is `scripts/state-machine.tsv`; an illegal event exits 3
and lists the legal events for the current state. See
`references/state-machine.md`.

## Base team

`base-skills/` ships four generic fallback skills — `scout` (investigator),
`developer` (primary implementer), `reviewer` (supporting validator),
`operator` (ops primary) — always discovered at lowest precedence, so a run
is never stuck in SELECTING for lack of candidates. Prefer a matching
domain skill; a user skill with the same name shadows the built-in.

## Discovery scope

Discovery is repo-scoped: `opsman map` and `opsman start` scan only
`<repo>/.claude/skills`, `<repo>/.agents/skills`, `<repo>/plugins`,
`$OPSMAN_SKILL_PATH` entries, and the built-in base team. Pass `--global`
(or set `OPSMAN_INCLUDE_GLOBAL=1`) to also scan `~/.claude/skills`,
`~/.claude/plugins/cache`, and `~/.agents/skills` — repo-local skills and
`$OPSMAN_SKILL_PATH` entries still shadow global ones. The choice is not
persisted: a later bare `opsman map` rebuilds repo-only, so re-run
`opsman map --global` if a run needs global skills again.

**Never hunt for skills or agents yourself** with `rg`/`grep`/`find` over
`$HOME`, other project folders, or the plugin cache — the registry built by
`opsman map` is the only source of capabilities. If a skill seems missing,
rebuild with `opsman map --global` or ask the user where it lives.

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

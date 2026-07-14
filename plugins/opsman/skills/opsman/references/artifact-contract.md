# Opsman Artifact Contract

## Exit codes (all scripts)

| Code | Meaning |
| --- | --- |
| 0 | ok |
| 2 | usage error / unknown verb |
| 3 | invalid state or illegal transition |
| 4 | lock held |
| 5 | schema, artifact, policy, dependency, or worktree invalid |
| 6 | budget exceeded |
| 7 | missing dependency (`jq`, `git`, sha256 tool) |

Errors go to stderr prefixed `opsman:`.

## Control-plane layout (target repo, gitignored)

    .opsman/
      registry/            skills.json agents.json scripts.json
                           capability-map.md registry.sha256
      runs/<run-id>/       state.json STATE.md events.jsonl handoff.md
                           attempts/ evidence/ tests/ reviews/ oracle/ context/
      worktrees/<run-id>/  isolated implementation and validation worktree
      current              run-id of the active run
      ledger.jsonl         append-only cross-run history (one record per
                           finished run; survives `opsman clean`)
      lock/                cooperative lock (mkdir-based; pid file inside)

## Per-run portable files

- `state.json` — authoritative machine state; shallow-validated against
  `schemas/state.schema.json` (required keys present).
- `events.jsonl` — append-only truth. One JSON object per line:
  `{seq, ts, event, from, to, payload}`. `seq` starts at 1 and increases
  by exactly 1. The last event's `to` always equals `state.json .status`.
- `STATE.md` — human-readable mirror, regenerated on every transition.
- `handoff.md` — regenerated on every transition; tells the next agent the
  current state, legal events, and next command.
- `result.md` — terminal states only (milestone 4).
- `pr-body.md` — written by `opsman deliver` (COMPLETED runs only):
  task title, provenance line, then `result.md`'s body verbatim. Derived
  and regenerable; safe to delete.
- `events.jsonl.rej` — quarantined torn journal tail (milestone 5): when a
  crash mid-append leaves the journal without a trailing newline, `opsman
  resume` terminates a complete final event in place, or moves an
  unparseable fragment here and rebuilds state from the remaining valid
  lines. `opsman record` refuses to append while such residue exists
  (exit 5) so a new event can never fuse with it.

## Milestone 2 planning artifacts (gate-enforced, JSON-in-.yaml)

- `problem.yaml` — analyst's structured problem statement (goal, domain,
  keywords, risk, acceptance_criteria, …); scaffolded by classify.sh.
- `candidates.json` — deterministic skill scores from select-skills.sh;
  every score explainable from its `signals` breakdown (most signals carry
  `matched`; `historical_success` carries `approved`/`total`/`rate` from
  the run ledger instead).
- `selected-skills.yaml` — the selector's 1–5 distinct picks with reasons,
  cross-checked against candidates.json.
- `plan.yaml` — acyclic step graph (id, uses, depends_on, risk R0–R4,
  success), validated by check-plan.sh.
- `acceptance.yaml` — executable checks (id, command, numeric
  expected_exit, optional risk and cwd).
- `context/<seq>-<role>.md` — rendered role packets; entitlements come from
  `scripts/roles.tsv` (state → role template → allowed {{TOKEN}}s).

`opsman validate-run` also re-checks that each of these still exists and
parses once its phase-exit event appears in the log.

## Milestone 3 execution artifacts

- `.opsman/worktrees/<run-id>/` — isolated source worktree for implementation
  and validation commands. The latest `WorktreePrepared` event mirrors the path
  into `state.json .worktree.path`.
- `evidence/<seq>-<kind>-<slug>/meta.json` — command metadata: command, cwd,
  timestamps, exit code, declared/effective risk, approval sequence, and output
  hashes.
- `evidence/<seq>-<kind>-<slug>/stdout.txt` and `stderr.txt` — captured command
  streams.
- `evidence/<seq>-<kind>-<slug>/diff.patch` — optional worktree status and diff
  captured after implementation or validation commands.

`ImplementationCompleted` requires a prepared worktree plus valid
`StepCompleted` evidence for every command-backed plan step, or a payload with
`manual_summary`. Non-R0 command-backed implementation evidence must include a
captured diff. `ValidationCompleted` requires, for every acceptance check, a
valid `AcceptanceChecked` evidence recorded in the **current** VALIDATING
cycle that matches `expected_exit` and the check's current command — evidence
from before a re-entry into VALIDATING (or for a since-edited command) does
not count. `WorktreePrepared`, `StepCompleted`, and `AcceptanceChecked` are
themselves gated on their payloads, so hand-recorded events cannot fake
execution facts.

## Milestone 4 judgment artifacts

- `limits.json` — per-run budgets written at init (`max_iterations`,
  `max_failed_attempts_per_hypothesis`, `max_changed_files`,
  `max_runtime_commands`); overridable only at `opsman start --limit`.
- Oracle verdict payloads (`schemas/oracle.schema.json`) — verdict word,
  rubric score breakdown, per-criterion evidence map, reason. Recorded via
  the four Oracle* events; `OracleApproved` is refused while any mechanical
  blocker holds.
- `ApprovalGranted` payloads carry `kind: command | continuation`
  (see `references/safety-policy.md`).
- `result.md` and `final.patch` — written by `finalize.sh` on every
  transition into COMPLETED, BLOCKED, or ABANDONED; regenerable by rerunning
  `finalize.sh <run-dir>`; `opsman validate-run` flags a terminal run
  missing either.

## Milestone 5 lifecycle verbs

- `opsman resume [<run-id>]` — the only mechanical way to reattach:
  repairs the journal tail (terminates a complete unterminated final
  event; quarantines a torn fragment to `events.jsonl.rej`), rebuilds
  `state.json` from the journal, regenerates `STATE.md`/`handoff.md`,
  validates artifacts (exit 5 stops the resume; a failed resume never
  moves `.opsman/current`), repoints `.opsman/current` on success, and
  prints the handoff plus the current role packet — all inside one lock
  cycle. Terminal and BLOCKED runs print the `result.md` location;
  WAITING_APPROVAL prints the pending approval kind.
- `opsman clean [--yes]` — dry run by default: lists finished runs (states
  in `OPSMAN_TERMINAL_STATES`) with their worktrees, orphan worktrees under
  `.opsman/worktrees/`, and a dangling `.opsman/current` pointer. `--yes`
  deletes them (`git worktree remove --force` plus a final prune) and
  clears `.opsman/current` if it named a removed run. BLOCKED and in-flight
  runs are never touched; there is no interactive prompt in either mode.
- `opsman deliver [<run-id>] [--branch <name>]` — COMPLETED runs only
  (exit 3 otherwise). Applies `final.patch` in a throwaway detached
  worktree at the pinned base revision, commits (message: task subject +
  run id + oracle verdict; no trailers), plants the branch (default
  `opsman/<run-id>`; exit 2 if it exists), removes the worktree, and
  writes `pr-body.md`. Takes the lock; never pushes; records no event —
  terminal states stay immutable and the branch is the evidence.

## Cross-run ledger

- `.opsman/ledger.jsonl` — append-only derived data: one JSON record per
  finished run (shape: `schemas/ledger.schema.json`), appended by
  `finalize.sh` after `result.md`/`final.patch`. `finalize.sh` is the only
  writer; a ledger failure warns and never fails finalize.
- Records land whenever finalize runs — COMPLETED, ABANDONED, and BLOCKED.
  A BLOCKED run that later resumes and finishes appends a newer record;
  readers dedupe by `run_id`, last record wins.
- Re-finalizing an unchanged run appends nothing: the candidate record is
  compared against the run's latest record ignoring `recorded_at`.
- The ledger is derived and regenerable (rerun `finalize.sh` while the run
  dir exists), so it gets none of the journal's torn-line repair: readers
  skip invalid lines. `opsman clean` never touches it.
- `opsman history [--json] [--limit <n>] [<run-id>]` is the reader:
  lock-free, ledger-only, never reads `runs/`.

## Writing rules

- Every write is atomic (`<file>.tmp` then `mv`) with one exception:
  `events.jsonl` is an append-only journal. If a crash lands between the
  event append and the `state.json` rewrite, the journal wins —
  `record-event.sh` detects a state file behind the log and rebuilds
  `status`/`seq`/`approval` from the events before proceeding.
- Only `record-event.sh` (via `opsman record`) mutates state, under the
  lock. Scripts never use `eval`.
- Locking is cooperative: `mkdir .opsman/lock`. The pid file records the
  invoking process's parent pid. A held lock is never broken
  automatically; a stale lock (dead pid) is reported for manual release.

## Write scope (`allowed_files`)

Optional per-step key in `plan.yaml`: a non-empty array of non-empty glob
patterns, relative to the worktree root; `*` crosses `/`. If any step
declares it, the plan is scoped and every dirty worktree file
(`git status --porcelain --untracked-files=all`, untracked included; both
sides of a rename) must match the union of all declared patterns.
Enforced at `run-step` (exit 5, evidence retained) and at the
`ImplementationCompleted` gate (exit 5, zero trace). `check-plan.sh`
rejects a malformed `allowed_files`; absence everywhere means unscoped.

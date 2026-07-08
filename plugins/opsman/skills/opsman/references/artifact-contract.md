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

## Milestone 2 planning artifacts (gate-enforced, JSON-in-.yaml)

- `problem.yaml` — analyst's structured problem statement (goal, domain,
  keywords, risk, acceptance_criteria, …); scaffolded by classify.sh.
- `candidates.json` — deterministic lexical skill scores from
  select-skills.sh; every score explainable from `signals.matched`.
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

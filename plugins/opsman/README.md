# opsman

A local-first **meta-agent orchestrator** for Dev and Ops tasks. Point it at a
problem, and it discovers the skills installed in your repo (plus, with
`--global`, your agent runtime's user-level skills), picks the smallest
suitable set, and drives the work through a
test-first, evidence-gated loop — with every step recorded on disk so the run
can survive crashes, new sessions, and even switching between Claude Code and
Codex mid-task.

## Main goal

Most agent sessions hold their plan, progress, and conclusions in conversation
memory: close the window and the work evaporates. Opsman moves all of that
into portable artifacts under `.opsman/` in your repository (gitignored), and
puts a POSIX shell kernel between the agent and that state.

The core stance: **agents reason, the shell proves.**

- The agent interprets your task, selects skills, plans, implements, and
  reviews.
- The `opsman` kernel owns discovery, the state machine, evidence capture,
  test execution, budgets, and validation. Every state change is a typed
  event appended to a journal; illegal transitions are refused mechanically.
- Completion is gated twice: a deterministic acceptance suite must pass
  (Layer A), and an independent Oracle role must approve against a scoring
  rubric — and the kernel re-checks the mechanical blockers, so an Oracle
  cannot approve past a failing test.

## How a run flows

```text
DISCOVERING → UNDERSTANDING → SELECTING → PLANNING → TEST_DESIGN
→ IMPLEMENTING → VALIDATING → JUDGING → COMPLETED

side states: DIAGNOSING, REPLANNING, WAITING_APPROVAL, BLOCKED, ABANDONED
```

Each state is owned by a role (discoverer, analyst, selector, planner,
implementer, verifier, critic, oracle). The kernel renders each role a
**context packet** containing only what that role is entitled to see — the
oracle, for example, gets the problem, plan, diff, and evidence, but never
the implementer's narrative. Red-before-green is enforced by the state
machine: you cannot enter `IMPLEMENTING` until an executable acceptance
check exists and a recorded baseline proves it currently fails.

Implementation happens in an isolated git worktree under
`.opsman/worktrees/<run-id>/`, bounded by the plan's declared **write
scope**: file-editing steps list `allowed_files` glob patterns, and the
kernel refuses any worktree change outside their union — per step at
`opsman run-step`, and again (covering manual agent edits) before
`ImplementationCompleted` is accepted. Opsman never pushes; the deliverable
is `final.patch` plus a `result.md` summary written mechanically when the
run reaches a terminal state.

## Installation

Claude Code (after adding the marketplace once with
`/plugin marketplace add glapsfun/cnative-skills`):

```text
/plugin install opsman@cnative-skills
```

Codex:

```bash
npx skills add glapsfun/cnative-skills --skill opsman --agent codex --global -y
```

Requirements: `git` and `jq` on PATH (the kernel fails fast with exit 7 if
either is missing). Runs must start inside a git repository. The optional
`opsman board` viewer additionally needs `python3`.

## How to use

### Start a run

```text
/opsman migrate the ingress manifests in ./deploy to Gateway API
```

The agent builds the skill registry, initializes a run, and starts working
through the lifecycle. You'll see it alternate between kernel calls
(`opsman next`, `opsman record`, `opsman validate`) and actual reasoning.
Ask it anything at any point — the run state is on disk, not in its head.

Budgets are set at start and only at start. To override a default:

```text
/opsman run with tighter budgets — use --limit max_iterations=3 for: fix the flaky e2e test
```

### Check progress

```text
/opsman-status
```

Prints the run's current state, task, and sequence number. For a finished
run it points at `result.md`, which contains the verdict, score table,
budget usage, and the evidence index.

### Watch a run live

```text
opsman board
```

Opens a read-only board at `http://127.0.0.1:41999` (pick another port with
`--port <n>`): a run switcher plus live plan progress, acceptance results,
budgets, the evidence index, the event tail, and the current handoff —
refreshed every couple of seconds while the agent works. It is GET-only,
binds loopback only, and never mutates `.opsman/`; no agent workflow depends
on it. This is the one opsman verb that needs `python3` — everything else
stays `git` + `jq`.

### Browse past runs

```text
opsman history
```

Every finished run leaves one record in `.opsman/ledger.jsonl` — task,
final state, oracle verdict and scores, skills used, budget usage, and
timestamps — appended mechanically when the run is finalized. `opsman
history` prints them newest first; `opsman history <run-id>` shows one
full record, `--json` emits machine-readable records, and `--limit <n>`
caps the table. The ledger lives outside `runs/`, so history survives
`opsman clean --yes`: cleaning reclaims disk, not memory.

### Land the result

```text
opsman deliver
```

For a COMPLETED run, deliver turns `final.patch` into a commit on a new
local branch — `opsman/<run-id>` by default, `--branch <name>` to choose —
created off the run's pinned base revision in a throwaway worktree. Your
current checkout is never switched or dirtied, and the patch cannot
conflict because it is applied at exactly the revision it was diffed
against. Deliver also writes `pr-body.md` (verdict, scores, evidence
index) into the run dir and prints the suggested `git push` + `gh pr
create` commands — printing only: opsman still never pushes. Only
oracle-approved (COMPLETED) runs can be delivered.

### Resume — after a crash, a new session, or in the other tool

```text
/opsman-resume
```

This is the headline feature. `opsman resume` repairs a crash-torn journal
tail, rebuilds state from the journal (the journal always wins), validates
every artifact, and prints a handoff addressed to "the next agent" plus the
current role's packet. Nothing depends on conversation memory, so:

1. Start a task in Claude Code, get as far as `IMPLEMENTING`.
2. Close the session. Open **Codex** in the same working tree.
3. Say "resume the opsman run" — the agent runs `opsman resume`, reads the
   handoff, and continues from exactly where the first agent stopped.

With several runs on disk, name one: `/opsman-resume ops-20260710-081500-a1b2c3`
(resume lists the known run ids if you don't know them).

### Validate on demand

```text
/opsman-validate
```

Re-runs the acceptance checks and reports pass/fail per check with evidence
pointers. Reporting only — it changes nothing.

### Clean up finished runs

Ask the agent to clean up; it runs `opsman clean`, which is a **dry run** —
it lists finished runs (COMPLETED/ABANDONED), their worktrees, orphan
worktrees, and dangling pointers, and deletes nothing. Only after you
confirm does it run `opsman clean --yes`. BLOCKED and in-flight runs are
never touched. The cross-run ledger is never touched either — cleaned
runs stay visible in `opsman history`.

## Example: what a run actually looks like

A condensed transcript of the kernel side of a small Dev task:

```console
$ opsman start "add a /healthz endpoint to the API server"
opsman: registry built: .opsman/registry (14 skills)
opsman: run ops-20260710-091205-f3ab12 initialized (state: DISCOVERING)

$ opsman next                      # → discoverer packet, then per role:
$ opsman record --event SkillsIndexed
$ opsman record --event TaskClassified        # analyst filled problem.yaml
$ opsman record --event SkillsSelected        # selector picked 1 skill, reasons recorded
$ opsman record --event PlanCreated           # plan.yaml: 3 steps, risk-classed, allowed_files-scoped
$ opsman record --event TestsDefined          # acceptance.yaml: curl check, expected exit 0
$ opsman record --event BaselineRecorded      # kernel verified the check FAILS today (red)
$ opsman worktree                             # isolated worktree created
$ opsman run-step s1                          # command steps run under policy, evidence captured
$ opsman record --event ImplementationCompleted
$ opsman validate                             # acceptance suite: green, evidence stored
$ opsman record --event ValidationCompleted
$ opsman judge                                # renders the oracle packet
$ opsman record --event OracleApproved --payload oracle/verdict.json
opsman: ops-20260710-091205-f3ab12: JUDGING + OracleApproved -> COMPLETED (seq 14)
```

The run directory now holds `result.md` (verdict, scores, budget usage) and
`final.patch` — apply it with `git apply .opsman/runs/<id>/final.patch`.
Or let the kernel do it: `opsman deliver` lands the same patch as a commit
on a fresh local branch with a PR body ready to go.

If the oracle had rejected instead, the run would route to `REPLANNING`; if
validation kept failing with identical output twice, the budget machinery
would refuse further attempts (exit 6) and force a replan or a clean stop —
no infinite loops.

## Safety model

- Every plan step declares a **risk class R0–R4**; the kernel refuses steps
  above the run's auto-approval ceiling (default R2).
- A deny-pattern policy (`kubectl apply`, `terraform apply`, force-push,
  credential/IAM changes, resource deletion, …) escalates a step's
  *effective* risk regardless of what the plan declared.
- R3/R4 steps park the run in `WAITING_APPROVAL`; the human's approval is
  recorded as a typed `ApprovalGranted` event (who/what/when), so the audit
  trail survives tool switches.
- **Write scope** — plan steps declare `allowed_files` glob patterns; the
  kernel fails straying steps and refuses `ImplementationCompleted` while
  out-of-scope worktree changes exist.
- Implementation is confined to the run's worktree; the main tree is the
  control plane. Opsman never pushes.

## What's inside

```text
plugins/opsman/
  commands/                 /opsman /opsman-resume /opsman-status /opsman-validate
  skills/opsman/
    SKILL.md                the orchestration protocol the agent follows
    agents/                 8 role prompt templates (analyst … oracle)
    base-skills/            built-in fallback team: scout, developer, reviewer, operator
    scripts/                POSIX sh kernel: opsman dispatcher + ~20 scripts, lib/
    scripts/board/          single-file live-board UI served by `opsman board`
    schemas/                JSON Schemas for state, events, plan, evidence, verdicts
    references/             architecture, state machine, safety policy, artifact contract
    tests/                  plain-sh unit tests (t-*.sh), no framework needed
    evals/evals.json        5 agent-behavior scenarios
```

Everything a run produces lives in the *target* repository:

```text
.opsman/                    (gitignored automatically)
  registry/                 discovered skills, capability map
  runs/<run-id>/            state.json, events.jsonl (truth), STATE.md,
                            handoff.md, plan/acceptance/problem artifacts,
                            evidence/, context/, result.md, final.patch
  worktrees/<run-id>/       isolated implementation worktree
  ledger.jsonl              append-only cross-run history (survives clean)
  current                   the active run id
  lock/                     cooperative lock
```

## When something goes wrong

Stable exit codes, always with an `opsman:`-prefixed message: **2** usage /
unknown run, **3** illegal transition (the error lists the legal events),
**4** lock held by another process, **5** artifacts inconsistent (run
`opsman validate-run`), **6** budget exceeded (the message names the limit
and the legal way out), **7** missing dependency.

Crash recovery is mechanical: a torn journal line is quarantined to
`events.jsonl.rej`, a complete-but-unterminated event is repaired in place,
and `opsman record` refuses to write on top of crash residue until a resume
has repaired it. See `skills/opsman/references/artifact-contract.md` for the
full contract.

## Works best with

Repo-local skills under `.claude/skills/`, `.agents/skills/`, or `plugins/`
— discovery is repo-scoped by default so the capability map stays free of
skills installed for other projects. To also orchestrate globally installed
skills (this catalog's `kubernetes-operator`, `fluxcd`, … from the plugin
cache, personal skills in `~/.claude/skills/`, or `~/.agents/skills/`), use
`opsman start --global` or `opsman map --global`; repo-local skills still
shadow global ones, and the choice is not persisted — a later bare
`opsman map` rebuilds repo-only. Existing skills work unmodified; an
optional `opsman.yaml` sidecar can add richer routing metadata.

Even with nothing installed, opsman is never teamless: four built-in base
skills — **scout** (investigation), **developer** (implementation),
**reviewer** (validation), **operator** (ops troubleshooting) — always
appear in the registry as lowest-precedence candidates. A domain skill
that matches the task outranks them, and any repo-local skill with the
same name shadows the built-in.

# Research playbook (Phase 2)

Goal: answer as many questions as possible **before** interviewing the user,
and produce an Evidence table where behavioral findings outrank stated ones.
Everything here is read-only.

## Order of cost — stop early when the picture is clear

### 1. This repo

- Locate the affected area: entry points, the code paths the symptom names,
  configs. For a performance complaint, find the request path before
  theorizing about it.
- Existing docs: `docs/`, READMEs, ADRs, runbooks. Someone may have already
  written the context you're about to ask for.
- **Prior investigations**: `docs/sre-incidents/INDEX.md` (sre-agent's
  incident memory) and `docs/pm/INDEX.md`. A confirmed incident root cause
  is the strongest evidence a bug-epic can cite.
- Tests around the area — they encode the currently-promised behavior.

### 2. History

- `git log --oneline -20 -- <affected paths>` — what changed recently, and
  does any change line up with "since when" in the request?
- `gh` when available: recent PRs touching the area
  (`gh pr list --state merged --search <area>`), open issues mentioning the
  symptom (`gh issue list --search <keywords>`). Missing/unauthenticated
  `gh` → note it in the ledger and move on.

### 3. Breadth — Explore subagents

When the layout is unknown or the sweep spans many files, dispatch
read-only Explore subagents (one per independent question, concurrently)
rather than grepping serially. Give each: the problem statement, the
specific question, and "return facts with file:line citations". Typical
splits: "where is X implemented", "what consumes Y", "what config governs
Z". No subagent support in the host → do the sweeps inline; same evidence,
slower.

## Evidence discipline

- Every finding: `[source] fact` — the source is a path:line, a command, a
  URL, or `[user]`.
- **Behavioral > stated.** A measurement, repro, log, or diff beats what
  the request claims. When they conflict, record both and the conflict —
  Phase 3 asks the user about it; Phase 4 lowers confidence.
- Facts, not interpretations. "p95 is 3.1s [dashboard]" is evidence;
  "the DB is slow" is a hypothesis — it goes in the ledger's `Hypothesis:`
  line, supported by evidence numbers.
- What you could not find out is as important as what you found: write it
  to `Open questions:` — that list *is* Phase 3's agenda.

## When the repo can't answer

No repo, empty repo, or the problem lives outside code (org process, third
party): research from the request text and any linked material alone, mark
epic confidence low, and prefer a discovery/spike task as T01 so the first
unit of work buys the missing evidence.

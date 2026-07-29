# Memory — the epic index and the product memo

Two stores under `docs/pm/` in the repo the skill is invoked in. Everything
recorded is metadata and reasoning — never secret values, tokens, or PII.

- `docs/pm/INDEX.md` — one row per epic; scanned every run (Phase 0).
- `docs/pm/pmanager-memo.md` — product context that outlives any one epic.

## INDEX.md schema

A single table, newest first:

```markdown
# PM index

| Epic | Title | Type | Status | Tasks | Primary metric | Updated |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| [app-performance](app-performance/epic.md) | Fix checkout latency | bug | in-progress | 2/5 done | p95 checkout < 800ms | 2026-07-28 |
```

`Tasks` is `<done>/<total> done`, where both counts exclude `descoped`
tasks. `Status` mirrors the epic frontmatter.

## Recall (Phase 0)

1. Scan INDEX for rows related to the current request — same service, area,
   or symptom, matched **semantically** ("slow app" matches a latency epic;
   "checkout bug" matches anything touching checkout).
2. Open matching epics; read their outcome: did the hypothesis hold? What
   did the validation show? What was ruled out?
3. Record matches in the ledger `Memory:` line and cite them in the new
   epic's **Related prior work** section. A prior epic's validated learning
   raises confidence; its failed hypothesis is a warning, not a veto.
4. Also check `docs/sre-incidents/INDEX.md` when present — an incident's
   confirmed root cause is high-grade behavioral evidence for a bug-type
   epic.

An update-mode or status-mode request resolves its target epic here: match
the user's wording against INDEX rows; ambiguous → ask which epic they mean.

## Memo

The memo stores what research cannot rediscover from code: business goals,
north-star metric, stakeholders and their concerns, product conventions,
and a decision changelog. Schema in `memo.template.md`.

**Trust rule:** memo facts are context, not evidence — an epic's Evidence
table cites code/history/users, never the memo alone. Stale memo entries
(contradicted by this run's research) are corrected, with a changelog line,
never silently kept.

## Write-back (Phase 6, and every update-mode run)

1. INDEX: add/refresh the epic's row. An epic directory found without an
   INDEX row gets its row added (reconcile, never regenerate the table from
   scratch — hand edits are legitimate).
2. Memo: add newly learned business goals/stakeholders/conventions; append
   one changelog line per run (`YYYY-MM-DD — spec'd app-performance;
   learned checkout is revenue-critical path`); refresh `_Last updated:_`.
3. Commit locally, scoped, inline message (this is the **canonical** commit
   rule — SKILL.md Phase 6 and tracking.md defer here):
   `git add docs/pm && git commit docs/pm -m "docs(pm): <what changed>"`
   (e.g. `docs(pm): spec app-performance`).
   The `git add` is required — new epics create untracked files a bare
   path-commit would miss. Never a bare `git commit`; never push; never a
   co-author line. Not a repo / conflicting unstaged changes → write files,
   note they're uncommitted.

## Edge cases

| Case | Behavior |
| :--- | :--- |
| No `docs/pm/` yet | Recall is a no-op; first Phase 6 creates dir + INDEX + memo |
| INDEX/file drift | INDEX is the scan source; missing referenced dir → note and skip; orphan dir → add its row |
| Slug collision | Different work, same natural slug → append `-2` |
| User edited docs by hand | Treat hand edits as authoritative; reconcile around them |

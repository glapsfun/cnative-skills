# Incident Memory

Phase 4 recalls resolved incidents to rank hypotheses; Phase 6 captures a new
one when a fix is validated. The store lives at `docs/sre-incidents/` in the
repo the agent is invoked in:

- `INDEX.md` — a compact signature table, one row per incident, read every run.
- `YYYY-MM-DD-<slug>.md` — one full record per **resolved** incident.

Everything recorded is metadata; **never a secret value** and never a raw log
dump that could carry tokens or PII. Reference services by the **same name**
used in the project memo's service map so the two stores cross-link.

## Signature

The match key. Four structured fields, surfaced in `INDEX.md`, drive recall:

- **service/workload** — the affected app (memo service-map name).
- **symptom class** — one of: crashloop, latency, errors, metrics, oom,
  networking, availability. This list is the **canonical** symptom-class
  vocabulary for recall; Phase 1 scoping words map onto it (see the semantic
  note below).
- **key error-or-metric signature** — the distinctive fingerprint, e.g.
  `OOMKilled exit 137`, `p99>3s on checkout`, `SchemaError in orders logs`,
  `AccessDenied: sts:AssumeRoleWithWebIdentity` (IRSA), `0/x nodes
  available: Too many pods` (EKS node/CNI capacity),
  `PermissionDenied: iam.serviceAccounts.getAccessToken` (GKE Workload
  Identity), `Insufficient regional quota` (GKE node pool/Autopilot
  capacity).
- **environment** — cluster / namespace.

Match **symptom class semantically**, not by exact string: Phase 1 may scope a
symptom with a different word (e.g. "performance" for latency, "deployment" for
a rollout failure) — map it to the nearest class here rather than missing a
real prior incident.

## Recall (Phase 4)

Runs during hypothesis ranking, **after** the current run's own evidence is
collected — prior art informs the ranking, it never short-circuits the loop.

1. If `docs/sre-incidents/INDEX.md` exists, scan it and filter by signature:
   same service/workload and symptom class first, then compare the
   error/metric fingerprint. If absent, note "no incident history" and continue.
2. For each candidate row, open its incident file and judge whether the current
   evidence genuinely matches — a signature hit is a lead, not proof.
3. A confirmed match **raises the confidence** of the matching root-cause
   hypothesis (ledger: `supported by [incident <slug>]`) and surfaces that
   incident's validated fix as a **candidate remediation** for Phase 5.

**Hard rule:** a recalled fix is re-validated against the current run, never
auto-applied. It enters Phase 5 as one option among others and still passes the
approval gate and the Phase 6 dry-run → validate cycle. If a candidate's
evidence does not hold, record "considered [incident], ruled out" rather than
forcing the match.

## Capture (Phase 6)

Runs as the final step **only when** a remediation was applied AND every
expected-behavior criterion passed (a validated resolution). Applied-but-
unverified, abandoned, and investigate-only runs write nothing.

1. Write `docs/sre-incidents/YYYY-MM-DD-<slug>.md` from
   `incident.template.md`, distilling the ledger: symptom, confirmed root
   cause, decisive evidence (each line with its `[source command/query]`), the
   validated fix + rollback, the validation criteria that passed, hypotheses
   ruled out, and links (dashboards/PRs/repos — no secret values).
2. Prepend one row to `INDEX.md` (newest first). If a row or file for this slug
   already exists from an interrupted prior capture, reconcile it in place
   rather than duplicating.
3. Stage and commit locally, scoped to the incident paths, with an inline
   message:
   `git add docs/sre-incidents && git commit docs/sre-incidents -m "chore(sre): capture incident <slug>"`.
   The `git add` is required because each capture creates a **new, untracked**
   incident file, which a bare `git commit <path>` would not stage.
   Never a bare `git commit` (editor hang / staged-index sweep). Never push;
   never add a co-author line. If the working dir is not a git repo, or the
   incident paths have unstaged conflicts you would disturb, write the files and
   note they were left uncommitted.

Writing incident memory is a local-documentation update, not a change to the
incident target — it is exempt from the read-only-until-approval gate (Safety
rule 1), touches no cluster, and stores no secret values.

## Edge cases

| Case | Behavior |
| :--- | :--- |
| No store yet | Recall is a no-op ("no incident history"); first capture creates the dir + `INDEX.md`. |
| Index/file drift | Index is the scan source of truth; a missing referenced file → note and skip; a resolved incident file with no index row → note the orphaned file and add its missing row. |
| Weak/near-miss signature | Treat as a lead the current evidence must confirm; if it doesn't hold, record "considered, ruled out". |
| Slug collision (same day/service) | Append a short disambiguator (`-2`). |

# Validation and Reporting

Phase 6 playbook: prove the fix worked with the same rigor used to find the
problem, then write it down.

## Post-change verification checklist

Run in order; every item cites a command and compares against the Phase 4
expected-behavior criteria:

1. **Rollout completed** —
   `kubectl rollout status deploy/$WORKLOAD -n $NS --timeout=180s`.
2. **Pods healthy** — `kubectl get pods -n $NS` — all Ready, and restart
   counts **stable across the observation window** (check twice, start and
   end).
3. **Expected-behavior criteria** — re-run each criterion's query exactly as
   recorded in the ledger (PromQL from `prometheus-analysis.md`, LogQL from
   `logs-investigation.md`) and record the value next to the threshold.
4. **No new error signatures** — the LogQL/`kubectl logs` error hunt over the
   post-change window must show nothing that wasn't present before.
5. **Alerts resolved** — Alertmanager API shows the incident's alerts gone
   (or explicitly still pending with a reason).
6. **GitOps in sync** — `flux get kustomizations -A` shows the fix revision
   applied / `argocd app get <app>` shows Synced + Healthy, so the fix won't
   be reverted.

## Observation window

Validate over the window defined in Phase 4 — default 15 minutes. For
intermittent symptoms the window must be **at least 3× the symptom period**
(a fault that appeared hourly needs 3 clean hours before claiming
resolution; say so and offer to check back rather than waiting silently).

## Verdicts

- **Resolved** — every criterion passed within the window → write the final
  report.
- **Applied but unverified** — the change is in but validation is impossible
  (no metrics access, window still open). State exactly what is unverified
  and what command the user should run later. Never upgrade this to
  "resolved" without the evidence.
- **Failed** — any criterion failed → record the failed hypothesis and its
  contradicting evidence in the ledger, and return to Phase 3. Consider
  whether to roll back the failed change first (offer it as an option).

## Final report format

Produce this skeleton, filled from the ledger. Offer to save it to a file
path the user names (e.g. `docs/incidents/YYYY-MM-DD-<slug>.md`):

```markdown
# Incident Report: <one-line title>

- **Date/time:** <first symptom> → <resolution> (<duration>)
- **Severity/impact:** <who/what was affected, how badly, user-facing or not>
- **Detection:** <how it was noticed — alert, user report, dashboard>

## Summary
<3-5 sentences: what broke, why, what fixed it>

## Timeline
| Time (UTC) | Event | Source |
| :--- | :--- | :--- |
| <ts> | <deploy/symptom/action> | <evidence: command, alert, commit> |

## Root cause
<the confirmed hypothesis with its mechanism and supporting evidence>

## Contributing factors
<conditions that allowed or amplified it — missing alert, tight limit, no probe>

## Actions taken
| Time (UTC) | Action | Result |
| :--- | :--- | :--- |

## Validation
| Criterion | Threshold | Observed | Verdict |
| :--- | :--- | :--- | :--- |

## Rollback information
<what was changed and the exact path back, should the issue recur>

## Follow-up recommendations
- <preventive action — alert on the leading indicator, CI validation, limit review>

## Links
<dashboards, commits/PRs, alerts, runbooks used>
```

Keep it blameless: name systems and conditions, not people. Facts a human
must supply (ticket links, user-impact numbers) are asked for, never
invented.

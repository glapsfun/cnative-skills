# Remediation Planning

Phase 5 playbook. Every option must be executable exactly as written after
approval — numbered steps with real commands or file edits, no hand-waving.
The approval gate is absolute: present, then stop.

## Option template

Fill this block for every option presented:

```markdown
### Option <N>: <name>
- **Description:** <what and why it addresses the ranked root cause>
- **Steps:** <numbered, exact commands or file edits, including the dry-run step>
- **Risk:** Low | Medium | High — <one-line justification>
- **Pros / Cons:** <bullets>
- **Expected impact:** <what changes for users/workloads during and after>
- **Rollback:** <exact commands/steps that restore the prior state; verify with what evidence>
```

## Risk classification

- **Low** — no user-visible interruption, trivially reversible: rolling
  restart, scale up, adding a read-only probe endpoint.
- **Medium** — brief interruption or a config/resource change requiring
  redeploy; rollback is a previous revision: rollout undo, limit changes,
  config fixes.
- **High** — schema or data changes, destructive operations (deletes,
  migrations), multi-service coordinated changes. Recommend extra human
  review and an explicit maintenance window; never bundle a high-risk step
  inside a lower-risk option.

## Standard playbook of options

Adapt these to the evidence; each is a complete Steps section.

**Restart** (stuck process, leaked state, config re-read):

```bash
kubectl rollout restart deploy/$WORKLOAD -n $NS
kubectl rollout status deploy/$WORKLOAD -n $NS --timeout=180s
```

Rollback: none needed — restart is idempotent; if pods fail to come back the
prior ReplicaSet is still available via `kubectl rollout undo`.

**Rollback a deployment** (issue started after a deploy):

```bash
kubectl rollout history deploy/$WORKLOAD -n $NS          # confirm target revision
kubectl rollout undo deploy/$WORKLOAD -n $NS             # or --to-revision=<n>
kubectl rollout status deploy/$WORKLOAD -n $NS --timeout=180s
```

Helm-managed: `helm history $RELEASE -n $NS` then
`helm rollback $RELEASE <rev> -n $NS`. GitOps-managed: use the GitOps path
below instead — a direct rollback will be reverted at the next sync.

**Resource-limit change** (OOMKilled with evidence that the limit is
genuinely too low):

```bash
kubectl patch deploy/$WORKLOAD -n $NS --dry-run=server -o yaml --type=strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"$CONTAINER","resources":{"limits":{"memory":"1Gi"}}}]}}}}'
# review the server dry-run output, then re-run without --dry-run=server
```

GitOps/Helm-managed: edit the values file or overlay in the source repo
instead (the patch above is revert-bait). Rollback: restore the previous
value the same way.

**Config fix** (evidence points at a wrong config value):

1. Locate the **source of truth** first — chart values, kustomize overlay,
   ConfigMap generator, or app config file in the repo. Never hand-edit a
   generated ConfigMap.
2. Make the edit in the source; show the diff.
3. Deploy through the normal path (GitOps sync, `helm upgrade`, CI) with its
   dry-run/preview first.

Rollback: revert the commit / restore the previous value; redeploy the same
way.

## GitOps execution paths

Flux-managed:

```bash
# after the fix commit lands in the source repo:
flux reconcile kustomization <name> --with-source
flux get kustomizations -A          # verify Applied revision
```

Argo-managed:

```bash
# after the fix commit:
argocd app sync <app>
argocd app get <app>                # verify Synced/Healthy
```

Emergency direct edit (only with explicit approval, only when waiting for
the Git path is not acceptable): suspend reconciliation first —
`flux suspend kustomization <name>` or `argocd app set <app> --sync-policy
none` — apply the manual change, and record in the ledger that reconciliation
is suspended and MUST be re-enabled after the proper fix lands
(`flux resume kustomization <name>` / `argocd app set <app> --sync-policy
automated`).

## Always offer

When confidence in the top hypothesis is medium or lower, include
**"collect more evidence"** as an explicit no-risk option, stating exactly
which discriminating test would raise confidence. Approving a fix and
approving more investigation are both legitimate outcomes of Phase 5.

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
   generated ConfigMap. When the source of truth is a Helm chart and the
   `helm` skill is installed, see `references/sibling-skills.md` for its
   CLI reference.
2. Make the edit in the source; show the diff.
3. Deploy through the normal path (GitOps sync, `helm upgrade`, CI) with its
   dry-run/preview first.

Rollback: revert the commit / restore the previous value; redeploy the same
way.

## GitOps execution paths

When the `fluxcd`/`argocd` skill is installed, verify the fix landed with
its diagnostic script instead of only the commands below — see
`references/sibling-skills.md`.

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

## AWS/EKS infrastructure changes

Node groups, IRSA roles, and AWS Load Balancer Controller configuration are
commonly managed by Terraform/CDK/eksctl rather than Flux/Argo. Check for
IaC ownership (e.g. `eksctl.io/...`/`terraform`-style tags on the node
group, role, or ALB) the same way `managedFields` reveals GitOps ownership
— an IaC-managed resource gets a fix directed at the IaC repo/PR, not a
direct `aws`/console mutation. A direct emergency change still needs
explicit acknowledgment that the next `terraform plan`/`apply` or `eksctl`
run will revert it (Safety rule 5).

Two concrete rules:

- **Prefer `desiredSize` over ASG edits.** Scale capacity via
  `aws eks update-nodegroup-config --cluster-name <cluster> --nodegroup-name
  <ng> --scaling-config desiredSize=<n>` (or the IaC equivalent) rather than
  editing the underlying Auto Scaling Group directly — the node group is the
  source of truth EKS reconciles against.
- **Never hand-edit `aws-auth` when EKS Access Entries are active.** Check
  `aws eks list-access-entries --cluster-name <cluster>` first — if it
  returns entries, the cluster's authentication mode has moved off the
  `aws-auth` ConfigMap and edits to it are silently ignored; use
  `aws eks create-access-entry`/`associate-access-policy` (or the IaC
  equivalent) instead.

If capacity is Karpenter-managed instead of a static node group (see
`sibling-skills.md`), the `desiredSize` rule above doesn't apply — defer to
the `karpenter` skill for NodePool/EC2NodeClass-level remediation instead.

## GCP/GKE infrastructure changes

Node pools, Workload Identity bindings, and GCE load-balancer/backend
configuration are commonly managed by Terraform or Config Connector rather
than GitOps. Check for IaC ownership (Config Connector's
`cnrm.cloud.google.com/*` annotations, or Terraform-style labels on the
node pool/backend service) the same way `managedFields` reveals GitOps
ownership — an IaC-managed resource gets a fix directed at the IaC repo/PR,
not a direct `gcloud`/console mutation. A direct emergency change still
needs explicit acknowledgment that the next `terraform plan`/`apply` will
revert it (Safety rule 5).

Two concrete rules:

- **Prefer node pool autoscaling bounds over manual resizing.** Scale
  capacity via `gcloud container clusters update <cluster> --node-pool <np>
  --enable-autoscaling --min-nodes=<n> --max-nodes=<n>` (or the IaC
  equivalent) rather than editing the underlying managed instance group
  directly — the node pool is the source of truth GKE reconciles against.
- **Autopilot capacity issues are a quota/regional-capacity investigation,
  not a scaling action.** There is no node pool to resize in Autopilot;
  check `gcloud compute regions describe <region>` quotas and
  `gcloud container operations list` for provisioning failures instead of
  proposing a manual scale.

## Writing a remediation script

When an option's Steps section requires writing or editing a script (a
one-off cleanup, batch scale, or migration helper) and the `bash-scripting`
skill is installed: apply its `references/02-defensive-patterns.md`
guidance while drafting the script, then run its `scripts/bash-lint.sh`
against the script before presenting the option to the user — see
`references/sibling-skills.md`. Without the skill, still follow basic
strict-mode hygiene (`set -euo pipefail`, quote all variable expansions) —
never hand the user an unquoted, unchecked script to run against
production.

## Always offer

When confidence in the top hypothesis is medium or lower, include
**"collect more evidence"** as an explicit no-risk option, stating exactly
which discriminating test would raise confidence. Approving a fix and
approving more investigation are both legitimate outcomes of Phase 5.

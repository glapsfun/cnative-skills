# Crossplane Remediation

Read during Phase 2/3 (detecting Crossplane and gathering evidence) and
Phase 4/5/6 (locating the resource, constructing and applying the fix)
whenever evidence shows the remediation target is Crossplane-managed —
either a cloud resource created via a Crossplane Provider (AWS, GCP, Azure,
SQL, Kubernetes-in-Kubernetes, …) or a Crossplane API itself (a Composite
Resource, a Claim, a Composition, a Function). Safety rule 5 still applies:
a direct cloud console/CLI or `kubectl edit` mutation to a Crossplane-owned
object needs explicit acknowledgment that the reconciler will revert it on
its next reconcile.

## 1. Detect Crossplane ownership

A resource is Crossplane-managed when it carries either signal:

- The `crossplane.io/composition-resource-name` annotation — set on every
  Managed Resource (MR) a Composition produced, naming the resource inside
  the Composition pipeline that created it.
- An `ownerReferences` entry pointing at a Composite Resource (XR) — the
  same "who owns this" check `managedFields`/owner references already give
  for GitOps ownership.

`scripts/sre-env-discovery.sh` reports whether Crossplane itself is
installed (`compositeresourcedefinitions.apiextensions.crossplane.io` CRD
present) as part of Phase 2 discovery — read that line before assuming
Crossplane is or isn't in play.

## 2. Read the resource tree and status conditions

Every Crossplane object (Provider, MR, XR, Claim) carries standard
Kubernetes `status.conditions[]` entries. Two condition types matter:

- **`Synced`** — whether Crossplane has successfully reconciled its desired
  state against the external API (or, for an XR, against its composed
  resources). `False` almost always means an external-API-facing error:
  read `.status.conditions[?(@.type=="Synced")].message` for the raw
  provider error.
- **`Ready`** — whether the resource is available for use. `Synced=True`
  with `Ready=False` means Crossplane's write succeeded but the external
  resource isn't available yet (propagation delay) or the readiness check
  itself is failing (e.g. a database still provisioning).

`scripts/crossplane-status-check.sh [TYPE[.VERSION][.GROUP][/NAME]]` is the
mechanical way to read these — the same "verify mechanically, don't trust
your own reading" principle `scripts/sre-snapshot.sh` and
`terraform-plan-check.sh` apply elsewhere. With no argument it sweeps every
Provider and every Managed Resource cluster-wide. With a `TYPE/NAME`
argument (both a kind and a name) it scopes to that single resource's tree
via `crossplane resource trace TYPE/NAME -o json` when the `crossplane`
CLI is present. With `TYPE` alone (no name) it classifies every resource of
that kind instead of one tree — still scoped by kind, just not to a single
instance. Either form falls back to the unscoped cluster-wide sweep (noted
in its output) when the `crossplane` CLI isn't present. A resource with no
Ready/Synced condition at all (not yet reconciled) is listed as unhealthy
too, not silently treated as healthy. It lists every unhealthy object with
its offending or missing condition(s) and reason, and exits `1` when any
are found — fold that list into the ledger's evidence, not just a summary
sentence.

When the `crossplane` CLI is available, `crossplane resource trace
TYPE[/NAME] -o wide` (or `-o dot` for a visual graph) is worth running
directly too — it renders the full Claim→XR→MR tree with per-node
Ready/Synced status in one read, faster than walking `kubectl describe`
across every composed resource by hand.

## 3. Classify the failure

| Symptom | Likely cause | Where to look |
| :--- | :--- | :--- |
| Provider `Installed=False` or `Healthy=False` | Package failed to unpack/activate, or its runtime pod is crashing | `kubectl describe provider <name>`; `kubectl logs -n crossplane-system deploy/<provider-pod>` |
| MR `Synced=False`, message mentions auth/credentials/403/permission | ProviderConfig references a missing/invalid Secret, or the provider's own cloud identity (IRSA for provider-aws, Workload Identity for provider-gcp) lacks permission | `kubectl describe providerconfig <name>`; cross-check the provider's cloud identity the same way `investigators/eks.md`/`investigators/gke.md` check IRSA/Workload Identity for any other pod |
| MR `Synced=False`, message is a cloud-API error (quota, invalid parameter, conflicting resource) | The external API itself rejected the write | The message *is* the evidence — treat it like any other cloud API error from `aws-investigation.md`/`gcloud-investigation.md` |
| MR `Synced=True`, `Ready=False` | External resource still provisioning, or its readiness check is failing | Compare against the resource's expected provisioning time; check the external service's own status if propagation has clearly stalled |
| XR/Claim stuck, Composition pipeline error in `Synced` message | A Composition Function failed or returned invalid output | `kubectl describe composition <name>`; Function pod logs if it's a Docker/Deployment-runtime Function |
| Claim creation rejected at admission | XRD schema validation failure | `kubectl describe xrd <name>`; the rejected object's own error message names the offending field |

## 4. Construct the fix

Locate the **source of truth** first — the XR, Claim, or Composition
manifest in the GitOps/source repository, not the generated MR. Never
hand-edit an MR's spec directly: Crossplane's reconciler treats the
Composition's rendered output as authoritative and will overwrite a
manual MR edit on the next reconcile, the same way a GitOps controller
overwrites a manual `kubectl edit` on a Flux/Argo-managed object.

Show the exact diff to the Claim/XR spec or Composition in the option's
Steps section — not a description of what to change. When the source of
truth lives in a Composition pipeline (a Function's input parameters, a
patch expression), match the file's existing conventions rather than
hand-rolling a parallel mechanism.

## 5. Dry-run before applying

Re-run `scripts/crossplane-status-check.sh` before proposing the fix to
capture the pre-fix baseline (the exact set of unhealthy objects the fix
must clear) and fold that list into the option's Risk field.

When Docker (or a local `crossplane` binary) and the XR/Composition/
Function YAML files are already available locally, `crossplane composition
render xr.yaml composition.yaml functions.yaml` renders the pipeline
offline and shows exactly what the change would produce — the closest
Crossplane equivalent to `terraform plan`/`pulumi preview`, though it
renders against the local manifests rather than diffing live cluster
state. Treat it as an optional extra dry-run, not a hard prerequisite —
`crossplane-status-check.sh`'s before/after comparison is the primary,
always-available gate.

## 6. Apply and rollback

Apply only after approval, through the normal GitOps path (`flux reconcile
kustomization ...` / `argocd app sync ...`) so the change reaches the
cluster the same way every other GitOps-managed fix does — see
`references/remediation.md`'s GitOps execution paths.

**Emergency direct edit** (only with explicit approval, only when waiting
for the GitOps path is unacceptable): annotate the target object with
`crossplane.io/paused: "true"` first — this is Crossplane's reconciliation
pause, the same role `flux suspend`/`argocd app set --sync-policy none`
play for GitOps — apply the manual change, and record in the ledger that
reconciliation is paused and MUST be resumed (remove the annotation) after
the proper fix lands in the source of truth.

Verify the fix by re-running `scripts/crossplane-status-check.sh` scoped to
the affected resource (or cluster-wide if scoping isn't available) and
confirming it now exits `0` — the same object list that was unhealthy in
step 5's baseline must be clean.

Rollback is a Git operation: revert the source-repo commit and let the
GitOps/Composition pipeline re-reconcile, verified the same way as the
original fix — a clean `crossplane-status-check.sh` afterward plus the
expected-behavior criteria from Phase 4.

## 7. Adoption/import is its own approval gate

Setting `crossplane.io/external-name` on a newly created MR to adopt an
already-existing external resource (rather than letting Crossplane create
a new one) changes what Crossplane believes it owns without changing the
external resource itself — this is a mutating-class action in its own
right, never a silent step inside an unrelated option's Steps section. If
evidence points at needing an adoption, propose it as its own remediation
option with its own risk, steps, and rollback (per `remediation.md`'s
option template).

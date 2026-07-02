# Disruption: consolidation, drift, expiration, budgets

Karpenter removes nodes through two classes of mechanism, and the distinction drives every
tuning decision:

- **Graceful (budget-limited):** consolidation (Empty/Underutilized) and drift. Candidates
  are checked against disruption budgets, a replacement is pre-spun and must go Ready
  before the old node drains.
- **Forceful (budgets ignored):** expiration (`expireAfter`), spot/health interruption,
  node auto-repair, manual NodeClaim deletion, static-pool scale-down. Expiration since v1
  drains immediately *without waiting for replacement capacity*.

PDBs and pod `terminationGracePeriodSeconds` are respected during any drain — but only
until the NodeClaim's `terminationGracePeriod` (if set) runs out.

## Consolidation

Three mechanisms, in order: delete empty nodes (parallel) → multi-node (N nodes → maybe 1
cheaper replacement) → single-node (1 → maybe 1 cheaper). Candidates favor fewer pods,
sooner expiry, lower-priority pods. Karpenter emits `Unconsolidatable` events explaining
why a node is kept (PDB named, "can't replace with a lower-priced node") — read them before
tuning blindly.

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized   # or WhenEmpty
  consolidateAfter: 5m
```

- `WhenEmptyOrUnderutilized` + `consolidateAfter: 0s` (the default) = maximum savings,
  maximum churn. Known pathology: nodes living 5–10 minutes before being repacked.
- `consolidateAfter` = quiet period after the last pod add/remove before a node is a
  candidate. Heuristics: **~5m** stable services, **10–15m** bursty workloads, **~30s**
  batch queues draining to zero, `WhenEmpty` + long window for stateful pools.
- **Spot nodes only consolidate by deletion** unless the `SpotToSpotConsolidation` feature
  gate is on, and **single-node** spot→spot replacement additionally requires **≥15 cheaper
  instance-type candidates** (anti race-to-the-bottom: walking down the price ladder lands
  on the most-interrupted pools; multi-node spot→spot has no such floor). Narrow spot pools
  never spot-consolidate.
- Upcoming (RFC accepted, not yet released as of v1.13): a third
  `consolidationPolicy: Balanced` that scores each move's savings against its disruption
  cost (pod priority / `controller.kubernetes.io/pod-deletion-cost`), and a WhenEmpty
  redefinition to "no positive-disruption-cost pods". Verify the user's version before
  recommending it.
- Consolidation binpacks on requests: pods with understated memory requests get OOM-killed
  when packed tighter. requests = limits for memory is the defense.
- Surge during deployments (extra node appears, then consolidates away minutes later) is
  expected; budget it if disruptive rather than disabling consolidation.

## Drift

A NodeClaim drifts when it no longer matches its NodePool/NodeClass. Field classes:

- **Dynamic** (can drift without you touching the CRD): `amiSelectorTerms` resolution (a
  new AMI release!), subnet/SG selector resolution, requirements vs node.
- **Static** (drift only on CRD edit, hash-compared): taints, labels, kubelet config,
  userData, tags.
- **Behavioral (never drift):** `weight`, `limits`, everything under `disruption`.

Drift is always-on since v1 (no gate). Replacement is launch-before-terminate and respects
budgets — this is the supported, controllable mechanism for AMI/K8s upgrades: pin the AMI,
bump the pin deliberately, let drift roll the fleet at the pace your `Drifted` budget
allows, with PDBs as the dead-man's switch against a bad AMI. Subtleties: *widening* a
requirement does not drift compatible nodes (narrowing does); static drift fires only on
CRD change so external node-mutating controllers don't cause churn loops; some Karpenter
version upgrades change the hash → whole-fleet drift after upgrade (tighten budgets first).

## Budgets

```yaml
disruption:
  budgets:
    - nodes: "20%"                       # ceil(total*pct) - alreadyDisrupting - notReady
      reasons: [Empty, Drifted]          # omit = all graceful reasons
    - nodes: "0"                         # block consolidation during business hours
      schedule: "0 9 * * mon-fri"        # cron, UTC!
      duration: 8h
      reasons: [Underutilized]
```

Default when unset: `{nodes: 10%}`. Multiple active budgets → most restrictive wins.
`nodes: "0"` with no schedule disables all *voluntary* disruption — it does not make nodes
immortal (expiration/interruption proceed). If you set per-reason budgets but no default
budget, unlisted reasons are unbounded. Production pacing examples: max 1 node per window
for change-sensitive fleets; `nodes: "0"` during control-plane upgrades, release afterwards
so drift replaces every node exactly once with the new AMI; `reasons: [Drifted]` windows to
confine upgrade rolls to maintenance hours.

## Protection layering (who may block what, and for how long)

Three levers, by owner, each bounded by the next:

1. **Workload owner — `karpenter.sh/do-not-disrupt` pod annotation.** Prefer the duration
   form: `"4h"` protects for 4h from pod start (v1.12+); `"true"` is indefinite — a
   forgotten `"true"` blocks node replacement forever. Blocks consolidation and drift; does
   NOT block expiration kick-in, interruption, repair, or manual deletion. Terminal pods
   (Succeeded/Failed) don't block.
2. **App owner — PDBs.** Respected during all graceful disruption and drains. A
   `maxUnavailable: 0` / `minAvailable: 100%` PDB blocks node replacement indefinitely —
   police these (Kyverno/OPA) rather than discovering them during an upgrade freeze.
3. **Cluster admin — `terminationGracePeriod` on the NodePool template.** The hard ceiling:
   countdown starts at drain start; pods are deleted early enough to honor their own
   `terminationGracePeriodSeconds` (a pod whose TGPS ≥ node TGP is deleted immediately);
   at the deadline remaining pods are force-deleted. With TGP set, drift can proceed past
   blocking PDBs/do-not-disrupt — that's the point (guaranteed patch velocity); warn
   workload owners. Without TGP, `expireAfter` + do-not-disrupt pods = nodes stuck
   half-drained forever (documented failure mode).

Node-level `karpenter.sh/do-not-disrupt: "true"` annotation (settable via
`template.metadata.annotations`) excludes whole nodes from voluntary disruption.

## Node auto-repair (alpha, self-hosted gate `NodeRepair`; built into Auto Mode)

Replaces nodes with persistent unhealthy conditions (Ready False/Unknown ~30m, accelerator
conditions ~10m). Forceful: ignores budgets, do-not-disrupt, and TGP (a broken node can't
drain reliably). Safety valve: skips if >20% of the NodePool is unhealthy.

## Termination mechanics worth knowing

- Every Karpenter node carries the `karpenter.sh/termination` finalizer → `kubectl delete
  node` is safe (cordon, drain, terminate instance, then remove finalizer). Deleting a node
  that *lacks* the finalizer leaves the EC2 instance running. `kubectl delete nodeclaim
  <name>` is the clean per-node recycle.
- Disrupting nodes are tainted `karpenter.sh/disrupted:NoSchedule` — DaemonSets do NOT
  implicitly tolerate it (unlike the cordon taint); add a toleration to daemonsets that
  must run to the end of drain.
- If replacement capacity fails to initialize (~10 min), the candidate is untainted and
  disruption retries.

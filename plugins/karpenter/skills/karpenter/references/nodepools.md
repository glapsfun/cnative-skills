# NodePool reference (`karpenter.sh/v1`)

The NodePool sets the *outer envelope* of what nodes may exist; pods narrow within it via
their own scheduling constraints (layered constraints model: effective constraint =
NodePool requirements ∩ pod constraints; no overlap = pod stays Pending, nothing launches).
Keep NodePools broad, push specificity into pod specs. Fewer, broader pools beat many narrow
ones — split only on real boundaries: GPU/arch/OS, team or billing isolation, different
disruption tolerance (stateful vs stateless).

## Spec at a glance

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels: {}            # stamped on every node (workload targeting)
      annotations: {}
    spec:
      nodeClassRef:          # group+kind+name all required (v1.1+)
        group: karpenter.k8s.aws   # eks.amazonaws.com on Auto Mode
        kind: EC2NodeClass         # NodeClass on Auto Mode
        name: default
      requirements: []       # see below
      taints: []             # pods must tolerate (isolation pattern)
      startupTaints: []      # removed by another controller (CNI/CSI); pods need NO toleration
      expireAfter: 720h      # default 720h; max node lifetime; FORCEFUL at expiry
      terminationGracePeriod: 48h  # nil = drain can block forever; set it
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized  # or WhenEmpty
    consolidateAfter: 5m     # defaults to 0s = max churn; Never disables consolidation
    budgets:
      - nodes: 10%           # default if unset; graceful disruption only
  limits:                    # aggregate caps; provisioning stops (silently) when exceeded
    cpu: "1000"
    memory: 1000Gi
    # nodes: "50"            # v1.11+; also custom resources like nvidia.com/gpu
  weight: 0                  # 0-100; higher tried first when pools overlap
```

Key semantics:

- **`expireAfter`** is a maximum, not a guarantee, and since v1 expiration is **forceful**:
  at expiry the node drains immediately *without waiting for replacement capacity* and
  ignores disruption budgets. PDBs/do-not-disrupt are respected only during drain, only
  until `terminationGracePeriod`. Max real lifetime = `expireAfter + terminationGracePeriod`.
- **`terminationGracePeriod`** (NodeClaim-immutable; changing it drifts nodes): hard
  deadline measured from drain start; pods are deleted *early* (deadline − pod's own
  `terminationGracePeriodSeconds`) so their grace is honored; at deadline remaining pods are
  force-deleted. With it set, drift can proceed past blocking PDBs and do-not-disrupt pods —
  by design (forced patching).
- **`startupTaints` vs `taints`** confusion is the #1 cause of provisioning loops: if a
  daemonset/bootstrap applies a taint Karpenter doesn't know about, Karpenter thinks pods
  can't schedule and keeps launching nodes. Declare such taints as `startupTaints`
  (e.g. `node.cilium.io/agent-not-ready`, `ebs.csi.aws.com/agent-not-ready`).
- **`limits`** are eventually consistent (parallel launches can briefly overshoot) and
  per-NodePool only (no cluster-wide limit). Leave headroom under limits or drift/upgrade
  replacements can't launch. Exhaustion is log-only (`...exceeds limit...`) — pair with an
  alert.
- **`weight`**: pods matching multiple pools otherwise get a *random* pool. Classic use:
  reserved/savings-plan pool at `weight: 50` with tight `limits` + unweighted spot/OD
  overflow pool. Caveat: weight is a scheduling preference under batching, not a hard
  guarantee.

## Requirements

```yaml
requirements:
  - key: karpenter.sh/capacity-type
    operator: In            # In | NotIn | Exists | DoesNotExist | Gt | Lt | Gte | Lte
    values: ["spot", "on-demand"]
    # minValues: 2          # optional diversity floor (see below)
```

- `Gt/Lt/Gte/Lte` take a single numeric string (`values: ["4"]`). `Gte/Lte` are Karpenter
  extensions (v1.9+) usable in NodePools and pod affinities.
- `minValues: N` forces the scheduler to keep ≥N unique values viable when binpacking a
  NodeClaim — a spot-diversity floor. High minValues constrains consolidation later.
  `MinValuesPolicy` operator option (v1.6+): `Strict` (fail scheduling) vs `BestEffort`
  (relax minValues).
- Hard cap: **100 requirements** per CRD (`MaxItems` on NodePool and NodeClaim). Labels
  aren't counted at NodePool admission, but template labels and propagated pod labels fold
  into the generated NodeClaim's requirements — heavily-labeled pods can push it over the
  100 at NodeClaim creation.
- Prefer `NotIn` exclusions (e.g. exclude metal/16xlarge) over `In` allowlists — keeps the
  diversity machinery working. Default universe (self-hosted, no requirements): all
  non-metal M/C/R/A/T(>2-series)/I types.

### Well-known labels

Cloud-agnostic (both variants): `topology.kubernetes.io/zone`,
`node.kubernetes.io/instance-type`, `kubernetes.io/arch` (amd64|arm64), `kubernetes.io/os`
(self-hosted only on Auto Mode — not supported there), `karpenter.sh/capacity-type`
(`spot` | `on-demand` | `reserved` — reserved = capacity reservations/ODCRs, NOT RIs;
priority order reserved > spot > on-demand), `karpenter.sh/nodepool`.

Self-hosted AWS labels (`karpenter.k8s.aws/`): `instance-category` (c/m/r/g/...),
`instance-family` (m5, g4dn), `instance-generation` (numeric — use Gt/Gte),
`instance-size`, `instance-cpu`, `instance-cpu-manufacturer` (aws|intel|amd),
`instance-memory` (MiB), `instance-network-bandwidth` (Mbps), `instance-ebs-bandwidth`,
`instance-local-nvme` (GiB), `instance-hypervisor` (nitro),
`instance-gpu-name/-manufacturer/-count/-memory`, `capacity-reservation-id`,
`capacity-reservation-type` (default|capacity-block), `instance-pods`,
plus `topology.k8s.aws/zone-id` (account-stable AZ ID).

Auto Mode uses `eks.amazonaws.com/instance-*` equivalents instead — full table in
[auto-mode.md](auto-mode.md). Using the wrong namespace silently matches nothing.

Custom labels: a requirement `{key: company.com/team, operator: Exists}` lets pods pick
arbitrary values via nodeSelector; Karpenter stamps the pod's value onto the node.

## How Karpenter schedules (what to tell workload owners)

- Sizes from **requests only** (limits = oversubscription); includes daemonset overhead.
  Binpacking is First-Fit-Decreasing; it then offers the chosen type + ~59 next-larger to
  EC2 Fleet (price-capacity-optimized for spot, lowest-price for on-demand).
- Direct pods to a pool: `nodeSelector: {karpenter.sh/nodepool: my-pool}`; keep others out
  with taints. Any well-known label works in nodeSelector/affinity, including Gt/Lt
  (e.g. `karpenter.k8s.aws/instance-local-nvme Gte "100"`).
- **Preferred (soft) constraints are treated as required first**, then relaxed one at a time.
  Consequence: preferred anti-affinity/ScheduleAnyway spreads inflate node count and degrade
  consolidation. Use `required` when it matters.
- **Karpenter does not balance AZs on its own.** HA workloads need
  `topologySpreadConstraints` on `topology.kubernetes.io/zone` (supported keys: zone,
  hostname, capacity-type). kube-scheduler places greedily on the first Ready node — use
  `minDomains` to force spread across in-flight nodes.
- Spot/OD ratio pattern: two pools with disjoint values of a custom `capacity-spread` label
  (spot: 1–4, OD: 5) + pod topologySpread on that key → 4:1 mix.
- PV topology is honored (pod → PVC → StorageClass allowedTopologies); a pod bound to a
  zonal EBS PV pins the node to that zone — zone-restricted NodePools must include it.
- GPUs/accelerators (`nvidia.com/gpu`, `aws.amazon.com/neuron`, ...): self-hosted nodes
  need the device-plugin daemonset or the node never reaches Initialized (Auto Mode bundles
  drivers/plugins).

## Static capacity (`spec.replicas`, alpha v1.8+; GA-equivalent in Auto Mode)

Fixed node count regardless of pod demand (RIs, compliance, latency-intolerant capacity).
One-way door: can't unset `replicas` (no static↔dynamic switch). No `weight`, only
`limits.nodes`, never consolidated, still drift-replaced (set `limits.nodes > replicas` for
replacement headroom). Scale: `kubectl scale nodepool <name> --replicas=N` — bypasses
budgets, respects PDBs. Zonal spread NOT auto-balanced: pin one pool per AZ if even spread
matters. Self-hosted requires the `StaticCapacity` feature gate.

## Canonical patterns

General-purpose pool (self-hosted), spot-first with OD fallback:

```yaml
requirements:
  - {key: kubernetes.io/arch, operator: In, values: ["amd64", "arm64"]}
  - {key: kubernetes.io/os, operator: In, values: ["linux"]}
  - {key: karpenter.sh/capacity-type, operator: In, values: ["spot", "on-demand"]}
  - {key: karpenter.k8s.aws/instance-category, operator: In, values: ["c", "m", "r"]}
  - {key: karpenter.k8s.aws/instance-generation, operator: Gt, values: ["4"]}
```

GPU isolation pool: instance-family/gpu-name requirement + `taints:
[{key: nvidia.com/gpu, value: "true", effect: NoSchedule}]`; workloads add the toleration,
a nodeSelector, and `resources.limits["nvidia.com/gpu"]`.

System/critical pool: `CriticalAddonsOnly` taint (CoreDNS and EKS add-ons tolerate it),
on-demand only, `budgets: [{nodes: "0"}]` if zero voluntary disruption is wanted (forceful
methods still apply).

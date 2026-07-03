# Deep Kubernetes Evidence

Second-tier evidence for when the standard sweep (pods, events, previous
logs, rollout state) is inconclusive. Self-sufficient: none of this requires
the `kubernetes-operator` plugin — though the SKILL.md rule stands: defer to
that plugin for deep Kubernetes work when it is installed.

All commands are read-only except where flagged **approval-needed** — those
create pods and must go through the orchestrator's approval gate, never run
directly by an investigator.

## Node-level

```bash
kubectl describe node <node>          # conditions, pressure, allocatable vs allocated, events
kubectl get events -A --field-selector involvedObject.kind=Node --sort-by=.lastTimestamp | tail -20
kubectl get leases -n kube-node-lease # kubelet heartbeat freshness (renewTime)
```

Pressure conditions (`MemoryPressure`, `DiskPressure`, `PIDPressure`) explain
evictions and scheduling refusals. `kubectl debug node/<n> -it
--image=busybox` gives a host-filesystem shell at `/host` — **approval-needed**
(creates a privileged pod); prefer node conditions + events first.

## NetworkPolicy tracing

```bash
kubectl get netpol -n $NS -o yaml     # podSelector, policyTypes, from/to rules
kubectl get pods -n $NS --show-labels # match selectors against actual pod labels
```

Decision rules:

- Any policy selecting the server pod with `policyTypes: [Ingress]` makes
  ingress **deny-by-default** for sources not listed in `from`.
- Check the *client's* namespace and pod labels against the `from` rules —
  namespace selectors are the usual mismatch.
- `podSelector: {}` selects every pod in the namespace: a default-deny.
- Remember policies are additive: any one policy allowing the traffic wins.

## DNS diagnostics

Read-only default — exec into an EXISTING pod:

```bash
kubectl exec <pod> -n $NS -- nslookup <svc>.<ns>.svc.cluster.local
kubectl exec <pod> -n $NS -- getent hosts <svc>.<ns>.svc.cluster.local   # when nslookup is absent
```

CoreDNS health:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

Creating a dedicated debug pod (`kubectl run dbg --rm -it --image=busybox
--restart=Never -- nslookup ...`) is **approval-needed** — offer it as an
option when no existing pod has DNS tooling.

## Storage / CSI

```bash
kubectl describe pvc -n $NS                    # binding state + events
kubectl get volumeattachments                  # node attach state per PV
kubectl get storageclass                       # provisioner + volumeBindingMode
kubectl get pods -n kube-system | grep -i csi  # CSI driver/controller health
```

Signatures: PVC `Pending` + `WaitForFirstConsumer` on the StorageClass with
an unschedulable pod is a deadlock (pod waits for volume, volume waits for
pod placement); `FailedAttachVolume`/`Multi-Attach error` events mean the
volume is still attached to a previous node.

## Control plane signals

Mostly hidden on managed clusters — record a GAP when unavailable:

```bash
kubectl get --raw /metrics 2>/dev/null | grep -E 'apiserver_request_duration|etcd_request_duration' | head
kubectl get events -n kube-system --sort-by=.lastTimestamp | tail -20   # scheduler/controller/leader-election churn
kubectl get componentstatuses 2>/dev/null                               # deprecated but still informative where served
```

Frequent leader-election transitions or apiserver latency spikes turn a
"random workload weirdness" incident into a control-plane incident — a
different blast radius and a different remediation conversation.

# Service Mesh Investigation

Applies when discovery detects Istio or Linkerd. Two consequences for every
mesh incident: the proxy sits in the request path (a whole new failure
surface), and mesh config is a first-class change source — a DestinationRule
edit is a "deploy" for timeline purposes, so the change-historian's window
must include mesh objects.

## Detection

```bash
kubectl get ns istio-system linkerd 2>/dev/null
kubectl get crd virtualservices.networking.istio.io serviceprofiles.linkerd.io 2>/dev/null
kubectl get pod <pod> -n $NS -o jsonpath='{.spec.containers[*].name}'   # istio-proxy / linkerd-proxy sidecar
kubectl get ds -n istio-system ztunnel 2>/dev/null                      # Istio ambient mode (no sidecars)
kubectl get ns $NS --show-labels                                        # istio-injection / linkerd.io/inject labels
```

## Istio evidence (read-only)

```bash
istioctl proxy-status                          # sync state + proxy/control-plane version skew
istioctl analyze -n $NS                        # config lint against the live cluster
istioctl proxy-config clusters <pod>.<ns>      # what the sidecar knows about upstreams
istioctl proxy-config routes <pod>.<ns>        # effective routing
kubectl get peerauthentication -A              # mTLS mode (STRICT/PERMISSIVE/DISABLE)
kubectl get virtualservice,destinationrule,gateway -n $NS -o yaml
kubectl logs <pod> -n $NS -c istio-proxy --tail=100
```

Envoy access-log response flags to grep for: `UF` (upstream connection
failure), `UO` (overflow/circuit breaker), `URX` (retry limit exceeded),
`NR` (no route), `UH` (no healthy upstream), `DC` (downstream closed).

## Linkerd evidence (read-only)

```bash
linkerd check
linkerd viz stat deploy -n $NS       # success rate, RPS, latency per deployment
linkerd viz edges deploy -n $NS      # who talks to whom, with identity
kubectl logs <pod> -n $NS -c linkerd-proxy --tail=100
kubectl get serviceprofiles -n $NS -o yaml
```

## Failure chains

| Chain | Mechanism | Discriminate by |
| :--- | :--- | :--- |
| mTLS mismatch | STRICT PeerAuthentication vs a sidecar-less client → connection resets at the proxy | client has no sidecar? `istioctl authn tls-check` equivalent evidence; resets only from non-mesh sources |
| Retry amplification | Aggressive VirtualService `retries` on an erroring upstream → traffic multiplies → latency collapse | upstream RPS ≫ downstream client RPS; `URX` flags; correlate with the retry-storm chain in `root-cause-analysis.md` |
| Misrouted traffic | DestinationRule subset labels not matching pod labels → `NR`/`UH` 503s | `istioctl proxy-config routes` shows the route; subset label vs pod label diff |
| Sidecar failure | Proxy OOM or version skew → intermittent 503s unrelated to the app | `istio-proxy` container restarts/memory; `proxy-status` skew column |
| Missing sidecar | Namespace label changed / injection webhook down → pod bypasses policy or is denied | pod has no proxy container; injection label on the namespace; webhook health |

## Remediation caveat

Mesh objects are usually GitOps-managed. Fixes to VirtualServices,
DestinationRules, PeerAuthentications, or injection labels follow the GitOps
execution paths in `remediation.md` — a hand-applied mesh change will be
reverted at the next sync, mid-incident.

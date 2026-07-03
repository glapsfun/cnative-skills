# Logs Investigation

Source selection order:

1. **Loki**, when discovery found it — fastest way to search across pods and
   time ranges.
2. **`kubectl logs`** — always available with cluster access; the only source
   for a crashed container's final output (`--previous`).
3. **Cloud logging** (CloudWatch Logs, GCP Cloud Logging, Azure Monitor) —
   v1 detects and mentions these; deep queries are out of scope. Tell the
   user which log group/filter to open.

## LogQL patterns

Port-forward Loki (`kubectl port-forward -n <ns> svc/loki 3100:3100`), then
query `query_range` with the incident window:

```bash
curl -fsS -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query=<logql>' \
  --data-urlencode 'start=2026-07-03T08:00:00Z' \
  --data-urlencode 'end=2026-07-03T11:00:00Z' \
  --data-urlencode 'limit=100'
```

Core queries (substitute `$NS`/`$WORKLOAD`):

```logql
# Error hunting across the workload
{namespace="$NS", pod=~"$WORKLOAD.*"} |~ "(?i)(error|exception|fatal|panic)"

# Error-rate trend (metric query — plot to find when errors started)
sum(rate({namespace="$NS"} |~ "(?i)error" [5m]))

# OOM / kill signatures
{namespace="$NS"} |~ "OOMKilled|signal: killed|Out of memory"

# Timeouts and connection failures toward dependencies
{namespace="$NS", pod=~"$WORKLOAD.*"} |~ "(?i)(timeout|timed out|connection refused|connection reset|EOF)"
```

Label discovery when you don't know what's indexed:

```bash
curl -fsS 'http://localhost:3100/loki/api/v1/labels'
curl -fsS 'http://localhost:3100/loki/api/v1/label/namespace/values'
```

## kubectl logs fallback

```bash
# Current logs, bounded
kubectl logs <pod> -n $NS --tail=200 --since=1h

# The CRASHED container's output — current logs of a restarted pod are the
# NEW attempt and often empty; --previous is where the answer is
kubectl logs <pod> -n $NS --previous --tail=100

# All containers in the pod (sidecars often hold the real error)
kubectl logs <pod> -n $NS --all-containers --tail=100

# Across all pods of the workload, with pod-name prefixes
kubectl logs -l app=$WORKLOAD -n $NS --prefix --tail=200

# Ingress controller logs when the symptom is request-facing (5xx, timeouts)
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# Control-plane view where accessible (managed clusters usually hide these)
kubectl logs -n kube-system -l component=kube-scheduler --tail=50
```

## Error taxonomy

Map each distinct signature to a failure class and its next diagnostic step:

| Log signature | Failure class | Next step |
| :--- | :--- | :--- |
| `connection refused`, `connection timed out` | Dependency down, wrong Service/port, or NetworkPolicy | Check the dependency's pods and EndpointSlices; `kubectl get netpol -n $NS` |
| `OOMKilled`, `signal: killed`, exit 137 | Memory limit hit | Memory-vs-limit queries in `prometheus-analysis.md`; leak vs traffic correlation |
| `permission denied`, `403`, `Forbidden` | RBAC (in-cluster) or cloud IAM | `kubectl auth can-i --as=system:serviceaccount:$NS:<sa>`; cloud IAM policy |
| `ImagePullBackOff`, `manifest unknown`, `unauthorized` | Registry/auth/tag | `kubectl describe pod` events contain the registry error verbatim |
| `failed to parse`, `invalid configuration`, `unknown flag` | Config error, usually from a recent change | Dispatch/consult `sre-change-historian` findings for config revisions |
| `tls: handshake failure`, `certificate has expired` | TLS/cert expiry | Check cert Secret ages and cert-manager events |
| Repeated identical requests with rising latency | Retry storm amplifying load | Traffic query vs upstream latency in `prometheus-analysis.md` |

## Correlation discipline

For every distinct error signature record the **first occurrence timestamp**
(narrow the `query_range` window or binary-search with `--since`). These
timestamps are the raw material for the incident timeline in
`root-cause-analysis.md` — an error class that started exactly at a deploy
time is a lead; one that predates the incident is background noise. Also
check the logs of the workload's direct dependencies over the same window:
the root cause frequently lives one hop downstream.

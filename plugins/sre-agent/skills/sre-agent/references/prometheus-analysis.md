# Prometheus Analysis

How to query Prometheus during an investigation. Reach the API through the
port-forward from `discovery.md` (`kubectl port-forward -n <ns> svc/<name>
9090:9090`), then query with `curl -fsS`:

```bash
# Instant query
curl -fsS -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=<promql>'

# Range query (history around the incident)
curl -fsS -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=<promql>' \
  --data-urlencode 'start=2026-07-03T08:00:00Z' \
  --data-urlencode 'end=2026-07-03T11:00:00Z' \
  --data-urlencode 'step=60s'
```

Substitute `$NS` and `$WORKLOAD` below with the investigation scope. Label
names vary per app (`job`, `service`, `pod`, custom) — verify with the metric
discovery section before trusting an empty result.

## Golden signals

```promql
# Traffic (RPS)
sum(rate(http_requests_total{namespace="$NS", pod=~"$WORKLOAD.*"}[5m]))

# Error rate (fraction of 5xx)
sum(rate(http_requests_total{namespace="$NS", pod=~"$WORKLOAD.*", code=~"5.."}[5m]))
  / sum(rate(http_requests_total{namespace="$NS", pod=~"$WORKLOAD.*"}[5m]))

# p99 latency (classic histogram)
histogram_quantile(0.99, sum by (le)
  (rate(http_request_duration_seconds_bucket{namespace="$NS", pod=~"$WORKLOAD.*"}[5m])))

# CPU usage vs requests
sum(rate(container_cpu_usage_seconds_total{namespace="$NS", pod=~"$WORKLOAD.*", container!=""}[5m]))
sum(kube_pod_container_resource_requests{namespace="$NS", pod=~"$WORKLOAD.*", resource="cpu"})

# Memory working set as % of limit, per pod
max by (pod) (container_memory_working_set_bytes{namespace="$NS", pod=~"$WORKLOAD.*", container!=""}
  / on (pod, container) kube_pod_container_resource_limits{resource="memory"} * 100)

# CPU throttling (fraction of periods throttled — >0.25 is significant)
sum(rate(container_cpu_cfs_throttled_periods_total{namespace="$NS", pod=~"$WORKLOAD.*"}[5m]))
  / sum(rate(container_cpu_cfs_periods_total{namespace="$NS", pod=~"$WORKLOAD.*"}[5m]))
```

Error-status label is `code` in some instrumentations and `status` in others;
gRPC uses `grpc_server_handled_total{grpc_code!="OK"}`.

## Kubernetes health (kube-state-metrics)

```promql
# Pods in non-Running, non-Succeeded state
kube_pod_status_phase{namespace="$NS", phase!="Running", phase!="Succeeded"} == 1

# Restart rate (restarts in the last hour)
increase(kube_pod_container_status_restarts_total{namespace="$NS", pod=~"$WORKLOAD.*"}[1h])

# OOMKilled containers in the last hour
increase(kube_pod_container_status_last_terminated_reason{namespace="$NS", reason="OOMKilled"}[1h]) > 0

# Pods not ready
kube_pod_status_ready{namespace="$NS", condition="false"} == 1

# Deployment: unavailable replicas
kube_deployment_status_replicas_unavailable{namespace="$NS", deployment="$WORKLOAD"} > 0

# Deployment: update stuck (generation mismatch)
kube_deployment_status_observed_generation{namespace="$NS", deployment="$WORKLOAD"}
  != kube_deployment_metadata_generation{namespace="$NS", deployment="$WORKLOAD"}

# HPA pinned at max replicas (scaling ceiling hit)
kube_horizontalpodautoscaler_status_current_replicas{namespace="$NS"}
  == kube_horizontalpodautoscaler_spec_max_replicas{namespace="$NS"}

# Node pressure conditions
kube_node_status_condition{condition=~"MemoryPressure|DiskPressure", status="true"} == 1
```

## Baseline comparison

An absolute number means little without a baseline. Two techniques:

```promql
# Same query, same time yesterday. The offset modifier must sit on the range
# vector selector, not on the aggregation — `sum(...) offset 1d` is a parse error.
sum(rate(http_requests_total{namespace="$NS", code=~"5.."}[5m] offset 1d))
```

And a range query spanning incident start − 2h to now (`query_range` with
`step=60s`) to see exactly when the curve broke.

A deviation is meaningful when it is **> 2× the baseline** or crosses a known
SLO bound — not when it wiggles within normal variance. Report the deviation
factor, the first timestamp where it exceeds the threshold, and hand that
timestamp to the timeline in `root-cause-analysis.md`.

## Metric discovery when names are unknown

```bash
# Is the target scraped at all? (the first question when "metrics disappeared")
curl -fsS -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up{namespace="$NS"}'

# All metric names for the namespace
curl -fsS -G 'http://localhost:9090/api/v1/label/__name__/values' \
  --data-urlencode 'match[]={namespace="$NS"}'

# Prove a metric is absent (returns 1 when the series does not exist)
curl -fsS -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=absent(http_requests_total{namespace="$NS"})'

# Scrape target status with error messages
curl -fsS 'http://localhost:9090/api/v1/targets' | head -c 2000
```

On Prometheus-Operator clusters, the scrape config comes from
ServiceMonitor/PodMonitor objects:

```bash
kubectl get servicemonitors,podmonitors -n $NS
```

A missing metric is usually one of: target down (`up == 0`), no
ServiceMonitor label match, relabeling dropped it, or the app stopped
exposing it (check `curl <pod-ip>:<metrics-port>/metrics` via
`kubectl exec`).

## SLO burn rate

Burn rate = observed error ratio ÷ error budget. For a 99.9% SLO the budget
is 0.001; the standard multiwindow pattern (Google SRE Workbook) pages when
both a long and a short window burn fast:

```promql
# Fast burn — pages: 14.4x budget over 1h AND 5m (2% of monthly budget in 1h)
(
  sum(rate(http_requests_total{namespace="$NS", code=~"5.."}[1h]))
    / sum(rate(http_requests_total{namespace="$NS"}[1h])) > (14.4 * 0.001)
and
  sum(rate(http_requests_total{namespace="$NS", code=~"5.."}[5m]))
    / sum(rate(http_requests_total{namespace="$NS"}[5m])) > (14.4 * 0.001)
)

# Slow burn — tickets: 6x budget over 6h AND 30m
(
  sum(rate(http_requests_total{namespace="$NS", code=~"5.."}[6h]))
    / sum(rate(http_requests_total{namespace="$NS"}[6h])) > (6 * 0.001)
and
  sum(rate(http_requests_total{namespace="$NS", code=~"5.."}[30m]))
    / sum(rate(http_requests_total{namespace="$NS"}[30m])) > (6 * 0.001)
)
```

During an incident: a fast-burn condition means mitigate now; a slow-burn
condition means investigate but the budget can absorb some deliberation.

## Alertmanager

```bash
# Active alerts for the namespace (port-forward Alertmanager on 9093 first)
curl -fsS 'http://localhost:9093/api/v2/alerts?filter=namespace%3D%22'$NS'%22'
```

For each active alert record: name, `startsAt`, and labels. The alert start
time is often the most precise "first symptom" timestamp available —
correlate it with the change timeline from the `sre-change-historian`
findings.

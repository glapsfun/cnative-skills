# Tracing Investigation

Traces decide incidents that metrics and logs can only gesture at: where in a
dependency chain latency accumulates, which downstream call errors first,
whether retries amplify load. Use this path when the symptom is latency-,
error-, or dependency-shaped and discovery found a trace backend.

Reach the backend via port-forward from `discovery.md`:

```bash
kubectl port-forward -n <ns> svc/tempo 3200:3200          # Tempo
kubectl port-forward -n <ns> svc/jaeger-query 16686:16686 # Jaeger
```

Substitute `$SVC`/`$DOWNSTREAM` with the affected and downstream service
names; compute the incident window rather than hardcoding epochs:

```bash
# Incident window: last 3 hours (portable epoch arithmetic; Tempo takes unix seconds)
END=$(date +%s)
START=$((END - 10800))
```

## Tempo (TraceQL)

```bash
# Slowest traces for the service in the incident window
curl -fsS -G 'http://localhost:3200/api/search' \
  --data-urlencode 'q={resource.service.name="$SVC" && duration > 1s}' \
  --data-urlencode "start=$START" \
  --data-urlencode "end=$END"

# Error-tagged spans
curl -fsS -G 'http://localhost:3200/api/search' \
  --data-urlencode 'q={resource.service.name="$SVC" && status=error}'

# Spans crossing a specific dependency edge
curl -fsS -G 'http://localhost:3200/api/search' \
  --data-urlencode 'q={resource.service.name="$SVC"} >> {resource.service.name="$DOWNSTREAM"}'

# Fetch one full trace by ID
curl -fsS 'http://localhost:3200/api/traces/<traceID>'
```

Tune the `duration >` threshold to ~2× the healthy p99 (from
`prometheus-analysis.md` baselines) so results are genuinely anomalous.

## Jaeger

```bash
# Service inventory (what is instrumented at all)
curl -fsS 'http://localhost:16686/api/services'

# Slow traces — timestamps are MICROSECONDS since epoch (scale the window up)
curl -fsS "http://localhost:16686/api/traces?service=$SVC&minDuration=1s&start=$((START * 1000000))&end=$((END * 1000000))&limit=20"

# One trace by ID
curl -fsS 'http://localhost:16686/api/traces/<traceID>'
```

## Reading a trace

Extract facts, not vibes:

- **Self-time vs child time** — total duration minus the sum of child spans
  is time spent in the service itself (CPU, GC, locks) rather than waiting
  on dependencies.
- **The slowest span** — record its service + operation; that is where the
  latency lives, and it is frequently *not* the service the user named.
- **Error tags** — `status=error` spans carry messages/status codes; the
  deepest erroring span is closest to the root cause.
- **Repeated sibling spans** — the same operation appearing N times under
  one parent is retry evidence; hand it to the retry-storm chain in
  `root-cause-analysis.md`.
- **Baseline shape** — fetch one pre-incident trace of the same operation
  when retention allows; a new span in the path means a dependency or
  code-path change.

## Correlation hops

- **Trace → log**: search logs for the trace ID (Loki:
  `{namespace="$NS"} |= "<traceID>"`; ELK: `query_string` on the trace-id
  field) — patterns in `logs-investigation.md` / `elk-investigation.md`.
- **Metric → trace**: Prometheus histogram responses can carry exemplars
  with trace IDs — jump straight from a latency spike to an example trace.
- **Log → trace**: structured logs with `trace_id` fields let you pivot from
  the first error line to its full request path.

## When there is no trace backend

Say so in the ledger and proceed metrics/logs-only: latency RCA falls back
to per-dependency latency metrics and timeout/retry log signatures — slower
and coarser, but workable. Note untraced services (absent from
`/api/services`) as instrumentation follow-ups for the final report.

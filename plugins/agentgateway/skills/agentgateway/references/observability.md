# agentgateway Observability Reference

## Metrics

Prometheus-compatible endpoint via `config.statsAddr` (static-only, set at startup). `config.metrics.{remove[], fields.add}` prunes or enriches metric labels.

## Tracing

OpenTelemetry OTLP export via `config.tracing`:

```yaml
config:
  tracing:
    otlpEndpoint: http://localhost:4317
    otlpProtocol: grpc              # or http
    path: /v1/traces                # default, http protocol only
    randomSampling: true            # CEL/float, default false
    clientSampling: true            # CEL/float, default true — honors client-provided sampling decisions
    headers: {}
    fields:
      remove: []
      add: {}
```

## Logging

```yaml
config:
  logging:
    level: info
    format: json                    # or text
    filter: ""
    fields:
      remove: []
      add: {}
    database:
      url: ""                       # optional — log to a DB for cost dashboards / virtual-key features
```

## Access Logs

`frontendPolicies.accessLog` (legacy static model) or the `frontend.accessLog` section of an `AgentgatewayPolicy` (Kubernetes) — supports CEL-computed field enrichment, e.g.:

```yaml
accessLog:
  add:
    backend: backend
```

## CEL Context (shared across metrics/tracing/logs/policies)

The same CEL surface (`schema/cel.json` / `cel.md`) is used identically for authorization rules, rate-limit cost expressions, transformations, and observability field enrichment — learning it once pays off everywhere. Highlights: `proxy.upstreamDuration`, `proxy.requestProcessingDuration`, `source.identity.serviceAccount`, `backend.{name,type,protocol}`, plus the MCP (`mcp.*`) and LLM (`llm.*`) surfaces documented in `references/mcp.md` and `references/llm-routing.md`.

## Admin UI

Default `http://localhost:15000/ui/` (bind wider with `ADMIN_ADDR` env var or `config.adminAddr`, both static-only — restart required to change). Read-only view of live proxy config in Kubernetes mode; editable in standalone mode (saving overwrites the config file and drops comments). Includes:

- An **LLM playground** (`/ui/llm/playground/`) for testing model/provider routing interactively.
- An **MCP tool playground** with an init/session flow for exercising federated MCP tools.

## `agctl`

Companion CLI for inspecting a running controller/proxy without going through the admin UI:

- `agctl proxy config` — dump the live proxy config.
- `agctl proxy trace` — live request tracing.
- `agctl controller log` — tail controller logs.
- `agctl costs import` — load a cost catalog for `llm.cost.*` CEL fields.

## Kubernetes-Specific: Control Plane Health

Because the control plane streams config to proxies over xDS, rollout safety depends on proxies actually **ACK**ing updates rather than rejecting them:

- Check control-plane metrics/logs for **NACK**s — a proxy that NACKs a config update is running on stale config, which won't be obvious from `kubectl get pods` alone.
- `kubectl describe gateway <name>` / `kubectl describe httproute <name>` for `status.conditions` — a resource can be `Accepted` at the Kubernetes level while still failing translation into the internal xDS resource model.
- If policies attached via `AgentgatewayPolicy` don't seem to be taking effect, first confirm the resource is even accepted (see `references/troubleshooting.md`) before assuming a merge-precedence issue.

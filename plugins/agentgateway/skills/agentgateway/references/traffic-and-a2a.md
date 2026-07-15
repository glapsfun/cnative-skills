# agentgateway Traffic Management & A2A Reference

## Route / Backend / Policy Shape

See `references/config-model.md` for the full route/backend schema and policy union. The key general-purpose traffic policies:

- **Weighted load balancing** on plain host backends:

  ```yaml
  backends:
  - host: example.com:8080
    weight: 1
  - host: 127.0.0.1:80
    weight: 9
  ```

- **`requestHeaderModifier` / `responseHeaderModifier`** — add/set/remove headers on the way in or out.
- **`transformations`** — request/response body/header transformation.
- **`requestRedirect`** — issue a redirect response instead of forwarding.
- **`urlRewrite`** — rewrite the path/host before forwarding to the backend.
- **`directResponse`** — return a fixed response without contacting a backend at all (useful for health-check stubs or maintenance pages).
- **`requestMirror`** — send a copy of traffic to a second backend without affecting the response the client sees (shadow testing).
- **`retry`** / **`timeout`** — standard resiliency controls.
- **`csrf`** / **`cors`** — standard cross-origin protections.
- **`buffer`** — control request/response buffering behavior.

These attach the same way regardless of whether the traffic is plain HTTP, MCP, LLM, or A2A — they're generic route/backend policies.

## A2A (Agent-to-Agent)

A2A support is enabled by tagging a route or backend as A2A traffic with the (empty) `a2a: {}` policy. agentgateway then applies A2A-aware processing/telemetry and, notably, **rewrites the agent card URL** (`/.well-known/agent.json`) so it points back at the gateway instead of the origin agent — this keeps future client requests flowing through the gateway rather than bypassing it after the first discovery call.

```yaml
binds:
- port: 3000
  listeners:
  - routes:
    - policies:
        cors: { allowOrigins: ['*'], allowHeaders: [content-type, cache-control] }
        a2a: {}
      backends:
      - host: localhost:9999
```

CORS is typically needed here too, for the same reason as MCP — browser-based A2A clients need explicit cross-origin allowances.

Logs on A2A traffic carry attributes like `a2a.method=message/stream`. CEL exposes `backend.protocol == 'a2a'` for policies/logging that need to distinguish A2A traffic from plain HTTP or MCP.

## When to Reach for Which Policy

| Need | Policy |
|------|--------|
| Split traffic across backend versions/weights | `backends[].weight` |
| Add/remove/rewrite headers | `requestHeaderModifier` / `responseHeaderModifier` |
| Transform request/response bodies | `transformations` |
| Serve a fixed response without hitting a backend | `directResponse` |
| Shadow-test a new backend safely | `requestMirror` |
| Protect against slow/failing backends | `retry`, `timeout` |
| Proxy an A2A agent safely (no bypass after discovery) | `a2a: {}` |
| Allow browser-based MCP/A2A clients | `cors` with the relevant exposed headers |

For MCP-specific policies (federation, session modes, MCP auth) see `references/mcp.md`; for LLM-specific routing see `references/llm-routing.md`; for auth/TLS/rate-limiting detail see `references/security.md`.

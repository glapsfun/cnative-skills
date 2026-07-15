# agentgateway Config Model Reference

## Two Coexisting Models

**Legacy (`binds`)** — explicitly marked `Deprecated; usage of gateways and routes is recommended instead` in `schema/config.json`, but still the model used by most current example files in the repo:

```yaml
binds:
- port: 3000
  listeners:
  - protocol: HTTP
    routes:
    - backends:
      - host: localhost:8000
```

**New (`gateways` + top-level `routes`/`tcpRoutes`)** — the recommended model for anything new:

```yaml
gateways:
  default:
    port: 3000
    listeners:
    - protocol: HTTP

routes:
- gateways: ["default"]              # or "default/<listener-name>" for one listener
  matches:
  - path: { pathPrefix: / }
  backends:
  - host: localhost:8000

tcpRoutes:
- gateways: ["default"]
  backends:
  - host: localhost:9000
```

`gateways` is a **map** keyed by gateway name → `LocalGateway { port, protocol, listeners[], tls, oidc, jwtAuth, authorization, extAuthz, extProc, cors, transformations, basicAuth, ... }`. If a gateway named `default` exists, route `gateways` strings default to it. `llm.gateways`, `mcp.gateways`, and `ui.gateways` attach the same way — `llm.port`/`mcp.port` are the deprecated equivalents.

Both models share the same inner route/backend/policy shapes — only the top-level nesting differs.

## Route / Backend Shape

```yaml
routes[]:
  name, namespace, ruleName, hostnames[], gateways
  matches[]:
    path: { exact | pathPrefix | regex }
    headers[]: { name, value: { exact | regex } }
    method
    query[]
  backends[]:
    service: { name, port } | backend | host | internal | dynamic | mcp
  policies: { ...full policy union... }
```

Weighted load balancing on plain host backends:

```yaml
backends:
- host: example.com:8080
  weight: 1
- host: 127.0.0.1:80
  weight: 9
```

## Full Policy Union

Attachable via `routes[].policies.<x>`, listener-level `gateways.<name>.listeners[].policies` (new model) / `frontendPolicies.<x>` (legacy static-file model), or a named entry in top-level `policies[]` (`{name, target: gateway|route|backend|listenerSet, phase: route|gateway, policy: {...}}`):

```
a2a, ai, apiKey, authorization, backendAuth, backendTLS, backendTunnel, basicAuth,
buffer, cors, csrf, directResponse, extAuthz, extProc, jwtAuth, localRateLimit,
mcpAuthentication, mcpAuthorization, mcpGuardrails, oidc, remoteRateLimit,
requestHeaderModifier, requestMirror, requestRedirect, responseHeaderModifier,
retry, timeout, transformations, urlRewrite
```

Listener-level-only policies (`frontendPolicies` in the legacy model): `accessLog, connect, http, logging, networkAuthorization, proxy, proxyProtocol, tcp, tls, tracing`.

## Other Top-Level Sections

- `llm:` — see `references/llm-routing.md`.
- `mcp:` — see `references/mcp.md`.
- `ui:` — expose the built-in web UI externally via `ui.gateways` + `ui.policies` (put `oidc` in front if you expose it beyond localhost).
- `services` / `workloads` — advanced, described in the docs as "mostly for testing"; use Kubernetes mode instead for normal service discovery.
- `routeGroups` — advanced route-delegation feature.
- `config:` — **static-only**, read once at startup, never hot-reloaded: `enableIpv6`, `dns.{lookupFamily,edns0}`, `adminAddr`, `statsAddr`, `readinessAddr`, `namespace`, `clusterId`, `trustDomain`, `session.key` (AES-256-GCM — generate with `openssl rand -hex 32`), `tracing.*`, `logging.*`, `metrics`, `backend.{keepalives,connectTimeout,poolIdleTimeout,poolMaxSize}`, `modelCatalog[]`, `customFunctions`, `standardAttributes.{user,group}` (CEL expressions for log attributes).

## Kubernetes CRDs (`agentgateway.dev/v1alpha1`)

- **`AgentgatewayBackend`** — defines non-Kubernetes-native backends: `spec.ai` (LLM provider) and `spec.mcp.targets[]` (MCP servers). `backend.ai` and `backend.mcp` policies **cannot target a plain Service** — they must target an `AgentgatewayBackend`.
- **`AgentgatewayPolicy`** — the policy CRD, `spec` split into three sections that mirror the standalone policy union but scope which resource kinds they can target:
  - `frontend`: `tcp, tls, http, networkAuthorization, accessLog, tracing` — targets **Gateway only**, applied before routing.
  - `traffic`: `cors, jwtAuthentication, basicAuthentication, apiKeyAuthentication, extAuth, authorization, rateLimit, extProc, transformation, csrf, headerModifiers, hostRewrite, directResponse, buffer, timeouts, retry` (this is their execution order) — targets Gateway, HTTPRoute, GRPCRoute, or ListenerSet.
  - `backend`: `tcp, tls, http, tunnel, transformation, auth, extAuth, health, ai, mcp` — targets Gateway, HTTPRoute, GRPCRoute, ListenerSet, Service, or AgentgatewayBackend.
- **`AgentgatewayParameters`** — referenced by the `GatewayClass` to customize the generated proxy Deployment (image, logging, etc.).

### Targeting and Merge Precedence

Targeting uses `targetRefs`/`targetSelectors` plus optional `sectionName` (a listener on a Gateway, a route rule on an HTTPRoute/GRPCRoute, or a port on a Service). **A single policy can only target one `kind`.**

Merge precedence (low → high), field-level/shallow — per-field last-writer-wins at the highest applicable precedence, no recursive merge inside a nested object:

- **`backend` policies:** Gateway < Listener < Route(targetRef) < Route rule(targetRef) < Backend(targetRef) < Backend(inline) < Route backend ref(inline)
- **`traffic` policies:** Gateway < Listener < Route < Route rule

### Standard Gateway API Support

`Gateway`, `HTTPRoute`, `GRPCRoute`, `TCPRoute`, `TLSRoute`, `ListenerSet`, `ReferenceGrant`, `BackendTLSPolicy` are all supported. `HTTPRoute.spec.rules[].backendRefs[]` can reference `group: agentgateway.dev, kind: AgentgatewayBackend` directly instead of a Service.

Service-level MCP contract: set `appProtocol: agentgateway.dev/mcp` on the Service so agentgateway knows to speak MCP to it, plus optional annotation `agentgateway.dev/mcp-path` (defaults `/sse` for SSE, `/mcp` for Streamable HTTP).

Conformance: supports GEP-91 (client cert validation), GEP-1494 (HTTP Auth), GEP-1713 (ListenerSets), GEP-1731 (HTTPRoute retries), GEP-1767 (CORS filter), GEP-2643 (TLSRoute), GEP-3567 (TLS updates for h2 coalescing). **Not** supported: GEP-1619 (session persistence), GEP-1748 (multi-cluster services), GEP-3155 (full backend mTLS — available via an extension instead), GEP-3388 (retry budgets).

## Verify Before Relying on Field Lists Above

`schema/config.json` (~11k lines) and its generated table `schema/config.md` (~60k lines) are regenerated directly from the Rust source on every release — this document is a map, not the territory. Grep the live schema, or check the installed version's docs page, before writing config for an unfamiliar field.

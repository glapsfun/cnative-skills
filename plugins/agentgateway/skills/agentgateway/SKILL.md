---
name: agentgateway
description: >
  Expert guide for agentgateway, the Linux Foundation AI-native proxy data plane (Rust,
  originally built by Solo.io, also used as kgateway's data plane). Covers MCP (Model
  Context Protocol) tool federation and multiplexing, A2A (agent-to-agent) proxying,
  multi-provider LLM/AI gateway routing (virtual models, weighted/failover/conditional
  routing, cost tracking), general HTTP/gRPC traffic management, security policies (JWT,
  OIDC, API key, CEL-based authorization, backend auth, rate limiting, TLS), observability
  (metrics, OpenTelemetry tracing, logging, admin UI), standalone binary/Docker
  configuration, and Kubernetes installation via Helm charts, Gateway API, and the
  AgentgatewayBackend/AgentgatewayPolicy CRDs. Use when the user mentions agentgateway,
  agentgateway.dev, MCP proxy/gateway/federation, A2A agent proxying, LLM gateway routing,
  AI gateway, virtual models, or asks an AI Gateway/MCP/LLM/agent-connectivity question that
  kgateway's own docs point elsewhere for.
---

# agentgateway User Guide

You are an expert on agentgateway, an open-source HTTP/gRPC data plane written in Rust that unifies traditional API traffic with AI-native traffic — LLM inference, MCP, and A2A — in a single proxy instead of running separate "regular" and "AI" gateways. It was originally built by Solo.io and donated to the Linux Foundation (Agentic AI Foundation); it is also the data plane that kgateway uses under the hood, and it is a fully conformant Kubernetes Gateway API implementation.

Adapt to the user's experience level. Someone asking "how do I run agentgateway locally?" needs different guidance than someone debugging CEL-based MCP authorization rules or virtual-model failover routing.

**Verify before you advise.** agentgateway's config schema is actively evolving and, at time of writing, mid-migration between two coexisting models:

- The low-level `binds`/`listeners`/`routes` model is marked **deprecated** in the schema in favor of a new top-level `gateways` (map) + top-level `routes`/`tcpRoutes` model.
- `llm.port` and `mcp.port` are likewise deprecated in favor of `llm.gateways` and `mcp.gateways`.
- Both forms are still live in current docs and examples simultaneously — show the new model as primary, but recognize the legacy form when a user pastes it from older docs or examples.

Before giving specific syntax:

- **Installed version and Kubernetes context in one shot:** run `scripts/agentgateway-version-check.sh` — it reports the latest upstream release vs. this skill's baseline, the local `agentgateway --version` output, and (if reachable) the Helm releases, control-plane images, and GatewayClass in the cluster, plus a reminder of the deprecated `binds`/`llm.port`/`mcp.port` keys to grep a config for.
- **Live config schema:** <https://agentgateway.dev/docs/standalone/latest/reference/configuration/schema/> or the repo's `schema/config.json` — it's generated directly from source (~11k lines), so a point-in-time field list here can lag. Run `scripts/agentgateway-doc-discover.sh` to list current `design/`, `examples/`, and `schema/` files straight from the upstream repo.
- **Gateway API CRD version:** check what's installed (`kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.labels}'` or similar) rather than assuming standard vs experimental channel

If you can't verify, use the examples in this skill but flag to the user that field names may differ in their installed version.

## Quick Reference

| Task | Command / pointer |
|------|------|
| Run standalone with a config file | `agentgateway -f config.yaml` |
| Run standalone with no config (bootstraps + opens admin UI) | `agentgateway` |
| Run via Docker | `docker run -v "$PWD/config.yaml:/config.yaml" -p 3000:3000 cr.agentgateway.dev/agentgateway:<version> -f /config.yaml` |
| Check version | `agentgateway --version` |
| Install on Kubernetes | See Deployment Modes / `references/installation.md` |
| Open the admin UI | <http://localhost:15000/ui/> (standalone default) |
| Federate multiple MCP servers | `mcp.targets[]` — see MCP section / `references/mcp.md` |
| Add an LLM provider | `llm.models[]` — see LLM Gateway section / `references/llm-routing.md` |
| Rate-limit by token cost | `localRateLimit` with `type: tokens` — see `references/security.md` |
| Inspect/trace a running proxy | `agctl proxy config`, `agctl proxy trace` |

## Deployment Modes

agentgateway runs in two modes that share the same policy/config surface:

**Standalone binary or Docker** — a single process reads a local YAML/JSON config file, which is watched and hot-reloaded (except the top-level `config:` section, read once at startup). Install:

```bash
curl -sL https://agentgateway.dev/install | bash          # add --version <ver> to pin a release
agentgateway -f config.yaml
```

Run with no `-f` at all and agentgateway bootstraps `~/.config/agentgateway/config.yaml` and starts the admin UI so the whole config can be built from there instead (note: saving from the UI overwrites the file and drops comments).

**Kubernetes** — a control plane watches Gateway API resources plus agentgateway's own CRDs and streams translated config to proxy pods over xDS (agentgateway's own protocol, not Envoy's). Install via Helm charts and create a `Gateway` with `gatewayClassName: agentgateway`; the controller auto-provisions a Deployment + Service. See `references/installation.md` for the full CRD-apply + Helm sequence and `references/config-model.md` for the CRDs themselves.

Use standalone mode for local development, single-process deployments, or anywhere outside Kubernetes; use Kubernetes mode when you want Gateway API-native lifecycle management, multi-team `targetRefs`-based policy attachment, or you're already running kgateway/Gateway API infrastructure.

## Architecture

Three equivalent configuration sources feed the same internal model:

1. **Static config** (env vars / flags) — read once at startup only.
2. **Local file config** (YAML/JSON) — the standalone mode; hot-reloaded on change (except `config:`).
3. **xDS** — the Kubernetes mode; a control plane built on **krt** (Istio's reactive collection library) watches Gateway API + agentgateway CRDs plus Services/Secrets/ReferenceGrants, translates them into agentgateway's own resource model, and streams it to proxies over gRPC ADS using agentgateway's own proto types (not Envoy's).

All three sources converge on the same in-memory internal representation inside the proxy: **Binds, Listeners, Routes, Backends, Policies, Addresses**.

## Core Config Model

**New model (primary — use this for anything new):** a `gateways` map plus top-level `routes`/`tcpRoutes` that attach to a gateway (and optionally a specific listener) via a `gateways` string field:

```yaml
gateways:
  default:
    port: 3000
    listeners:
    - protocol: HTTP

routes:
- gateways: ["default"]          # or "default/<listener-name>" to target one listener
  matches:
  - path: { pathPrefix: / }
  backends:
  - host: localhost:8000
```

**Legacy model (deprecated, still seen in older docs/examples):** explicit nested `binds`/`listeners`/`routes`:

```yaml
binds:
- port: 3000
  listeners:
  - protocol: HTTP
    routes:
    - backends:
      - host: localhost:8000
```

`llm:`, `mcp:`, and `ui:` are simplified top-level sections that skip the routing model entirely and attach to a gateway the same way (`llm.gateways`, `mcp.gateways`, `ui.gateways`) — see the MCP and LLM sections below. `policies[]` lets you define a named, reusable policy once and attach it by `target` (`gateway`/`route`/`backend`/`listenerSet`) instead of inlining it everywhere.

Routes support simple weighted load balancing directly on `backends[]`:

```yaml
backends:
- host: example.com:8080
  weight: 1
- host: 127.0.0.1:80
  weight: 9
```

On Kubernetes, the same policy surface is expressed through the `AgentgatewayPolicy` CRD (`frontend`/`traffic`/`backend` sections) and non-Kubernetes-native backends (LLM providers, MCP targets) through `AgentgatewayBackend`. Merge precedence, `targetRefs`/`sectionName` targeting, and the full policy union are in `references/config-model.md`.

## MCP (the flagship feature)

agentgateway can front one or more MCP servers and multiplex them into a single virtual MCP server exposed over Streamable HTTP (and legacy SSE). Four target kinds:

- `stdio: { cmd, args, env }` — spawn a local MCP server process
- `mcp: { host, port, path }` — remote server, MCP Streamable HTTP transport
- `sse: { host, port, path }` — remote server, legacy SSE transport
- `openapi: { host, port, path, schema }` — synthesize MCP tools automatically from an OpenAPI spec

```yaml
# yaml-language-server: $schema=https://agentgateway.dev/schema/config
mcp:
  port: 3000
  policies:
    cors:
      allowOrigins: ["*"]
      allowHeaders: [mcp-protocol-version, content-type, cache-control, mcp-session-id]
      exposeHeaders: ["Mcp-Session-Id"]
  targets:
  - name: time
    stdio: { cmd: uvx, args: ["mcp-server-time"] }
  - name: everything
    stdio: { cmd: npx, args: ["@modelcontextprotocol/server-everything"] }
```

Every target listed under one `mcp:` (or `backends[].mcp`) block is federated into one endpoint — this is agentgateway's tool-federation feature. CORS exposing `Mcp-Session-Id` is required for browser-based MCP clients/inspectors. `mcp.statefulMode` controls session handling: `stateful` (default) pins follow-up calls to the same upstream by session ID; `stateless` auto-wraps each call with an init sequence so stateless upstreams (e.g. OpenAPI-backed) work per-request. `mcp.failureMode` (`failClosed`|`failOpen`) controls behavior when a target is unhealthy.

MCP has its own auth/guardrail policies distinct from generic HTTP auth — `mcpAuthentication` (JWT with named-IdP shortcuts for Auth0/Keycloak/Okta/Descope, plus the OAuth Protected Resource Metadata MCP's discovery flow expects), `mcpAuthorization` (CEL rules keyed on `mcp.tool.name`/`jwt.*`), and `mcpGuardrails` (external policy processors). See `references/mcp.md` for the full auth model, session/CEL details, and the OpenAPI-to-MCP synthesis workflow.

## LLM / AI Gateway Routing

Two ways to configure LLM backends, sharing the same provider union (`openAI`, `anthropic`, `bedrock`, `azure`, `gemini`, `vertex`, `copilot`, `custom`):

1. `backends[].ai` — attach an AI backend to a route like any other backend (works with either config model, or `AgentgatewayBackend` on Kubernetes).
2. `llm.models[]` / `llm.providers[]` / `llm.virtualModels[]` — simplified, model-name-centric config auto-served under standard OpenAI-shaped paths (`/v1/chat/completions`, `/v1/models`, ...).

```yaml
llm:
  port: 4000
  models:
  - name: smart
    provider: openAI
    params: { model: gpt-5.5, apiKey: $OPENAI_API_KEY }
  - name: anthropic/*
    provider: anthropic
    params: { apiKey: $ANTHROPIC_API_KEY }
```

The distinctive feature is **virtual models**: publish one client-facing model name that dynamically routes to real `llm.models` entries via `routing.weighted.targets[]` (weighted load balancing), `routing.failover.targets[]` (priority tiers — degrades to the next tier if a tier is unhealthy), or `routing.conditional.targets[]` (first matching CEL expression wins, for content-based routing). `llm.models[].visibility: internal` hides a model from direct client requests so it's only reachable through a virtual model, and `llm.models[].authorization.rules[]` gives per-model CEL RBAC.

`custom` provider entries with `formats[]` (`completions`/`messages`/`responses`/`embeddings`/`rerank`/`realtime`/...) are how you point at any OpenAI-compatible endpoint (Ollama, vLLM, Groq, DeepSeek, Together AI, OpenRouter, xAI, or a Kubernetes Gateway API Inference Extension `InferencePool`). See `references/llm-routing.md` for full provider-specific fields, cost catalog config, and the CEL telemetry surface (`llm.inputTokens`, `llm.cost.*`, etc.) available to policies, rate limits, and logs.

## A2A and General Traffic Policies

Tag a route/backend fronting an A2A agent with the (empty) `a2a: {}` policy; agentgateway then applies A2A-aware processing and **rewrites the agent card URL** (`/.well-known/agent.json`) to point back at itself, so future client requests don't bypass the gateway:

```yaml
routes:
- gateways: ["default"]
  policies:
    cors: { allowOrigins: ["*"], allowHeaders: [content-type, cache-control] }
    a2a: {}
  backends:
  - host: localhost:9999
```

Beyond AI-specific traffic, agentgateway is a full general-purpose data plane: retries, timeouts, header modifiers, request/response transformations, direct responses, CSRF, CORS, request mirroring, redirects, and URL rewrites are all available as route/backend policies — see `references/traffic-and-a2a.md`.

## Security

- **Auth methods:** `jwtAuth` (generic HTTP; `mcpAuthentication` is the MCP-specific equivalent), `apiKey`, `basicAuth`, `oidc` (browser login flow), `extAuthz`/`extProc` (call out to a gRPC service).
- **CEL-based authorization:** `authorization.rules[]` (HTTP) / `mcpAuthorization.rules[]` (MCP) — each rule is an `allow`/`deny`/`require` CEL expression evaluated against request/JWT/MCP context.
- **Backend auth** (credentials sent *to* upstreams): `passthrough` (forward the validated inbound JWT), `gcp` (ID token/access token), `aws` (SigV4 signing, including `assumeRole` with CEL-expression session tags — useful for Bedrock/AgentCore cost attribution), `azure`, `oauthTokenExchange` (RFC 8693 token exchange).
- **TLS:** `backendTLS` for upstream connections (client certs, SNI, ALPN), listener `tls.mode`/`minTLSVersion`/`maxTLSVersion`.
- **Rate limiting:** `localRateLimit` (token bucket; `type: tokens` lets you rate-limit by LLM token cost instead of request count) and `remoteRateLimit` (calls an external rate-limit service with CEL-computed cost per descriptor).

Full field-level detail, provider-specific auth shapes, and example CEL rules are in `references/security.md`.

## Observability

- **Metrics:** Prometheus-compatible endpoint via `config.statsAddr`.
- **Tracing:** OpenTelemetry OTLP export via `config.tracing` (`otlpEndpoint`, `otlpProtocol: grpc|http`, sampling rates).
- **Logging:** structured text/JSON logs via `config.logging`, with CEL field add/remove.
- **Admin UI:** `http://localhost:15000/ui/` by default (bind wider with `ADMIN_ADDR` env var or `config.adminAddr`) — includes an LLM playground and an MCP tool playground; read-only in Kubernetes mode, editable in standalone mode.
- **`agctl`** — companion CLI for inspecting a running controller/proxy: `agctl proxy config`, `agctl proxy trace`, `agctl controller log`, `agctl costs import`.

See `references/observability.md` for the full CEL context available to metrics/tracing/log enrichment and Kubernetes-specific control-plane monitoring (xDS ACK/NACK).

## agentgateway ↔ kgateway Boundary

This mirrors the "AI Gateway and Agentgateway Boundary" section in `plugins/kgateway/skills/kgateway/SKILL.md` — if that section's scope ever changes, update both together. kgateway's own docs explicitly route AI Gateway, MCP, LLM, and agent-connectivity questions here. The split: **agentgateway** owns MCP tool federation, A2A proxying, LLM/AI gateway routing, and virtual models; **kgateway** owns generic Kubernetes Gateway API/Envoy traffic routing (HTTPRoute/TCPRoute, TrafficPolicy, ListenerPolicy, Istio integration). The two compose rather than compete — agentgateway is the data plane kgateway uses under the hood, and agentgateway can also run as its own independent `GatewayClass` (`agentgateway`) alongside or instead of kgateway. If a user's question is really about generic HTTP routing/Envoy behavior with no MCP/A2A/LLM angle, point them to the kgateway skill instead.

## Debugging

**Hot-reload gotcha:** everything in the config file hot-reloads except the top-level `config:` section (adminAddr, logging, tracing, dns, session, namespace, clusterId, ...), which is read once at startup — a restart is required for changes there to take effect.

**Kubernetes mode:** check xDS ACK/NACK status (a NACK'd config means the proxy rejected an update — check control-plane and proxy logs), `kubectl describe gateway`/`kubectl describe httproute` for `status.conditions`, and confirm the `AgentgatewayPolicy`/`AgentgatewayBackend` CRDs the resource references actually exist and are accepted.

**Standalone mode:** hit the admin UI (`:15000/ui/`) for a live view of loaded config, or `agctl proxy config` / `agctl proxy trace` for a CLI view.

Common issues (MCP session/CORS failures, GatewayClass not provisioning a proxy, provider-auth failures, the config-model migration tripping up copy-pasted examples) are in `references/troubleshooting.md`.

## Reference Files — read when tasks go deeper

| File | Read when the task involves |
|------|---------------------------|
| `references/installation.md` | Standalone binary/Docker/source install, Kubernetes Helm charts + Gateway API CRDs, GatewayClass, uninstall |
| `references/config-model.md` | Full `gateways`/`routes` vs legacy `binds` comparison, the complete policy union, Kubernetes CRDs (`AgentgatewayBackend`, `AgentgatewayPolicy`, `AgentgatewayParameters`), targeting and merge precedence |
| `references/mcp.md` | MCP target kinds, multiplexing, session modes, CORS, `mcpAuthentication`/`mcpAuthorization`/`mcpGuardrails`, OpenAPI-to-MCP synthesis |
| `references/llm-routing.md` | LLM provider union and provider-specific fields, `llm.models` vs `backends[].ai`, virtual models (weighted/failover/conditional), cost catalog and CEL cost telemetry |
| `references/traffic-and-a2a.md` | Route/backend/policy shape, weighted load balancing, transformations/redirects/rewrites, A2A `a2a: {}` policy and agent-card rewrite |
| `references/security.md` | JWT/API key/basic/OIDC auth, CEL authorization rules, backend auth (passthrough/GCP/AWS/Azure/token exchange), TLS, local/remote rate limiting |
| `references/observability.md` | Metrics, OpenTelemetry tracing, logging, CEL field enrichment, admin UI, `agctl` |
| `scripts/agentgateway-version-check.sh` | Checking the installed CLI/Kubernetes version against the latest upstream release, or a reminder of deprecated config keys to grep for |
| `scripts/agentgateway-doc-discover.sh` | Listing current `design/`, `examples/`, and `schema/` files straight from the upstream GitHub repo |
| `references/troubleshooting.md` | Systematic diagnosis, hot-reload/`config:` gotcha, xDS ACK/NACK, MCP session/CORS failures, provider-auth failures |

## Helpful Links

- Docs: <https://agentgateway.dev/docs/standalone/latest/> (standalone) and <https://agentgateway.dev/docs/kubernetes/latest/> (Kubernetes)
- GitHub: <https://github.com/agentgateway/agentgateway>
- Design docs: <https://github.com/agentgateway/agentgateway/tree/main/design>
- Examples: <https://github.com/agentgateway/agentgateway/tree/main/examples>
- Config schema: <https://github.com/agentgateway/agentgateway/tree/main/schema>
- Release notes: <https://github.com/agentgateway/agentgateway/releases>

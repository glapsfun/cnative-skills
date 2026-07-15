# agentgateway MCP Reference

MCP (Model Context Protocol) support is agentgateway's flagship feature: it can front one or more MCP servers and multiplex them into a single virtual MCP server exposed over Streamable HTTP (and legacy SSE).

## Target Kinds

Configured under `mcp.targets[]` (simplified top-level section) or `backends[].mcp.targets[]` (route/backend-attached). Each target has a `name` plus one of:

- **`stdio: { cmd, args, env, clear_env }`** — spawn a local MCP server process.

  ```yaml
  - name: time
    stdio: { cmd: uvx, args: ["mcp-server-time"] }
  ```

- **`mcp: { host, port, path, backend }`** — remote server, MCP **Streamable HTTP** transport (the Kubernetes CRD equivalent calls this a `static` target with `protocol: MCP`, `backendRef`).

  ```yaml
  - name: mcp2
    mcp: { host: http://localhost:3001/mcp }
  ```

- **`sse: { host, port, path, backend }`** — remote server, **legacy SSE** transport (Kubernetes CRD: `protocol: SSE`).
- **`openapi: { host, port, path, schema: { file | url } }`** — synthesizes one MCP tool per OpenAPI operation automatically; no MCP-aware server required on the upstream side.

Each target can carry its own `policies` (header modifiers, transformations, `backendTLS`, `backendAuth`) independent of the others.

## Multiplexing / Federation

Every target listed under one `mcp:` (or `backends[].mcp`) block is federated into **one virtual MCP server** — this is the tool-federation feature:

```yaml
backends:
- mcp:
    targets:
    - name: time
      stdio: { cmd: uvx, args: ["mcp-server-time"] }
    - name: everything
      stdio: { cmd: npx, args: ["@modelcontextprotocol/server-everything"] }
```

A client sees one MCP endpoint; agentgateway routes each tool/prompt/resource call to the target that owns it.

## Session Handling

`mcp.statefulMode: stateful | stateless` (default `stateful`):

- `stateful` — tracks session IDs and pins subsequent calls from the same client to the same upstream instance.
- `stateless` — auto-wraps each request with an init sequence so stateless upstreams (e.g. OpenAPI-backed targets) still work correctly per-request.

`mcp.failureMode: failClosed | failOpen` (default `failClosed`) controls behavior when a target is unhealthy. `mcp.prefixMode: always | conditional` controls whether tool names are prefixed with the target name to avoid collisions across federated targets.

## CORS (Required for Browser Clients)

MCP responses use the `Mcp-Session-Id` header, which browsers won't expose to JavaScript without an explicit CORS allow-list — required for browser-based MCP clients/inspectors:

```yaml
mcp:
  policies:
    cors:
      allowOrigins: ["*"]
      allowHeaders: [mcp-protocol-version, content-type, cache-control, mcp-session-id]
      exposeHeaders: ["Mcp-Session-Id"]
```

## Minimal Working Example

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
  - name: everything
    stdio:
      cmd: npx
      args: ["@modelcontextprotocol/server-everything"]
```

(`mcp.port` is deprecated in favor of `mcp.gateways` — see `references/config-model.md`.)

## MCP Auth (distinct from generic HTTP auth)

- **`mcpAuthentication`** — `issuer`, `audiences[]`, `provider.{auth0|keycloak|okta|descope}` (derives sensible JWKS URL + resource metadata defaults for these named IdPs), `resourceMetadata` (OAuth Protected Resource Metadata, needed for MCP's own discovery flow), `jwks.{file|url}`, `mode: strict|optional|permissive`, `authorizationLocation` (header / queryParameter / cookie / CEL expression).
- **`mcpAuthorization.rules[]`** — CEL rules, each an `allow`/`deny`/`require` expression evaluated against MCP + JWT context:

  ```yaml
  mcpAuthorization:
    rules:
    - 'mcp.tool.name == "echo"'
    - 'jwt.sub == "test-user" && mcp.tool.name == "get-sum"'
    - 'mcp.tool.name == "get-env" && jwt.nested.key == "value"'
  ```

- **`mcpGuardrails.processors[]`** — an ordered list of external policy-processor services (`service`/`host`/`backend` ref) that can inspect and reject MCP requests/responses; the first rejection in the chain short-circuits it.

Full example combining JWT auth with tool-level CEL authorization:

```yaml
mcp:
  port: 3000
  policies:
    cors: { allowOrigins: ["*"], allowHeaders: ["*"], exposeHeaders: ["Mcp-Session-Id"] }
    backendAuth: { passthrough: {} }
    jwtAuth:
      issuer: agentgateway.dev
      audiences: [test.agentgateway.dev]
      jwks: { file: ./manifests/jwt/pub-key }
    mcpAuthorization:
      rules:
      - 'mcp.tool.name == "echo"'
      - 'jwt.sub == "test-user" && mcp.tool.name == "get-sum"'
  targets:
  - name: mcp2
    mcp: { host: http://localhost:3001/mcp }
```

## CEL Context for MCP Policies

Available wherever MCP policies (authorization, guardrails, logging) evaluate CEL: `mcp.methodName`, `mcp.sessionId`, `mcp.tool.{target,name,arguments,result,error}`, `mcp.prompt.{target,name}`, `mcp.resource.{target,name}`.

## Kubernetes Equivalent

On Kubernetes, MCP targets are declared on an `AgentgatewayBackend`'s `spec.mcp.targets[]` rather than the standalone file's `mcp:`/`backends[].mcp`. `backend.mcp` policies (from `AgentgatewayPolicy`) must target the `AgentgatewayBackend`, not a plain `Service` — see `references/config-model.md` for the CRD targeting rules. The Service-level MCP contract (`appProtocol: agentgateway.dev/mcp`, optional `agentgateway.dev/mcp-path` annotation) still applies when a target ultimately resolves to a Kubernetes Service.

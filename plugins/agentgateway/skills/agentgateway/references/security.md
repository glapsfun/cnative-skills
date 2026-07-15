# agentgateway Security Reference

## Authentication

- **JWT (`jwtAuth`, generic HTTP traffic)** — `mode: strict|optional|permissive`, `location.{header{name,prefix}|queryParameter|cookie|expression(CEL)}`, `providers[]: {issuer, audiences[], jwks.{file|url}, jwtValidationOptions.requiredClaims[]}`. Only `exp, nbf, aud, iss, sub` are ever enforced; default `requiredClaims` is `["exp"]`. For MCP traffic use `mcpAuthentication` instead (see `references/mcp.md`) — it's a distinct policy with MCP-specific discovery/resource-metadata fields.
- **API key auth (`apiKey`)** and **basic auth (`basicAuth`)** — simple credential checks.
- **OIDC (`oidc`)** — full browser login flow: `issuer`, discovery document, `authorizationEndpoint`/`tokenEndpoint`, `tokenEndpointAuth: clientSecretBasic|clientSecretPost`.
- **External authorization (`extAuthz`)** and **external processing (`extProc`)** — delegate request/response inspection or mutation to an external gRPC service.

## Authorization (CEL-based RBAC)

`authorization.rules[]` (generic HTTP) — each rule is `{allow|deny|require: <CEL expression>}`, evaluated against request/JWT/backend context. For MCP-specific tool-level authorization use `mcpAuthorization.rules[]` (CEL against `mcp.tool.name`, `jwt.sub`, etc. — see `references/mcp.md`).

```yaml
authorization:
  rules:
  - 'jwt.sub == "admin" || request.path.startsWith("/public")'
```

## Backend Auth (credentials sent *to* upstreams)

`backendAuth` covers how agentgateway authenticates itself to whatever it's proxying to:

- **`passthrough: {}`** — forward the inbound validated JWT/credential as-is to the upstream.
- **`key: {file|value}` + `location`** — attach a static API key.
- **`gcp: {idToken|accessToken}`** — Google credentials, using an ADC-compatible credential file.
- **`aws`** — SigV4 request signing: `accessKeyId`, `secretAccessKey`, `region`, `sessionToken`, `serviceName` (e.g. `bedrock`, `bedrock-agentcore`, `execute-api`), `assumeRole.{roleArn, sessionName, tags[]}` — `tags` can be CEL expressions, useful for per-request cost/session attribution when calling Bedrock or AgentCore.
- **`azure.{explicitConfig(clientSecret|managedIdentity|workloadIdentity)|developerImplicit|implicit}`**.
- **`oauthTokenExchange`** — RFC 8693 token exchange, swapping an inbound credential for a backend-scoped token (used for Cross-App-Access / ID-JAG-style flows).

## TLS

- **`backendTLS`** (outbound, to upstreams) — `client cert/key/root`, hostname/SNI override, `insecure`/`insecureHost` escape hatches, ALPN, `keyExchangeGroups: X25519|P-256|P-384|X25519_MLKEM768`.
- **Listener TLS** — `tls.mode: static|dynamicCa`, `minTLSVersion`/`maxTLSVersion: TLS_V1_0..TLS_V1_3` (in practice only 1.2/1.3 are actually supported/negotiated).
- **mTLS ambient identity** — `source.identity.{trustDomain,namespace,serviceAccount}` (SPIFFE, delivered over an HBONE tunnel), tying into Istio ambient-mesh integration via `config.trustDomain`, `config.additionalTrustDomains`, `config.skipValidateTrustDomain`.

## Rate Limiting

- **`localRateLimit[]`** — in-process token bucket: `maxTokens`, `tokensPerFill`, `fillInterval`, `type: requests|tokens`. `type: tokens` rate-limits by LLM token cost instead of request count — the cost expression defaults to `llm.totalTokens`, so this is the mechanism for capping how many LLM tokens a client can burn per interval:

  ```yaml
  localRateLimit:
  - maxTokens: 10000
    tokensPerFill: 1000
    fillInterval: 60s
    type: tokens
  ```

- **`remoteRateLimit`** — calls an external rate-limit service (e.g. Envoy's `ratelimit`), with `domain`, `descriptors[].cost` (a CEL expression), and a per-descriptor `service`/`host`/`backend` ref.

## CORS / CSRF

Standard allow-origins/headers/methods/credentials shape under `cors`; `csrf` for cross-site request forgery protection. Both are needed more often than you'd expect on MCP and A2A traffic specifically — see `references/mcp.md` and `references/traffic-and-a2a.md` for the exact headers those protocols require exposed.

## Verify Before Advising

Auth and rate-limit fields are part of the same actively-regenerated schema as everything else in agentgateway — cross-reference `schema/config.json` or the installed version's docs page rather than assuming every field listed here is present or named identically in the user's version, especially for newer surface like `oauthTokenExchange` and AWS `assumeRole` tags.

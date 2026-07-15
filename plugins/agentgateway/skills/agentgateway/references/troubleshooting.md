# agentgateway Troubleshooting Reference

## Systematic Diagnosis

```
1. Which mode is this — standalone or Kubernetes?
   Standalone: check the admin UI (:15000/ui/) or `agctl proxy config`
   Kubernetes: kubectl get pods -n agentgateway-system

2. Is the config the process is running actually the config you think it is?
   Standalone: remember the top-level `config:` section is static-only —
     changes there require a restart, everything else hot-reloads.
   Kubernetes: check the control plane logs for xDS ACK/NACK on the latest push.

3. Is the Gateway/route accepted?
   kubectl describe gateway <name> -n agentgateway-system
   kubectl describe httproute <name> -n <namespace>
   → status.conditions[type=Accepted/Programmed].status: True

4. Is the proxy pod actually running the config you expect?
   agctl proxy config   (or admin UI, standalone)
   kubectl logs deploy/<gateway-name> -n agentgateway-system   (Kubernetes)

5. For MCP/A2A specifically: is this a protocol-level failure (session/CORS)
   or a routing failure (wrong target/backend)? Reproduce with `agctl proxy trace`.
```

## Hot-Reload / `config:` Gotcha

**Symptom:** you changed `adminAddr`, `logging`, `tracing`, `dns`, `session`, `namespace`, or another top-level `config:` field, saved the file, and nothing changed — even though adding a new route elsewhere in the same file *does* take effect live.

**Cause:** the top-level `config:` section is read once at process startup; it is explicitly excluded from the file watcher that hot-reloads the rest of the config.

**Fix:** restart the agentgateway process. There is no way to apply a `config:`-section change without a restart in standalone mode.

## GatewayClass Not Provisioning a Proxy

**Symptom:** created a `Gateway` with `gatewayClassName: agentgateway`, but no Deployment/Service appears.

**Causes and fixes:**

- The `agentgateway` control plane isn't running or hasn't reconciled yet — check `kubectl get pods -n agentgateway-system` and control-plane logs.
- The Gateway API CRDs installed don't match what the controller expects (standard vs experimental channel) — verify with `kubectl get crd gateways.gateway.networking.k8s.io -o yaml` rather than assuming.
- `AgentgatewayParameters` referenced by the `GatewayClass` has an invalid image/config — `kubectl describe gatewayclass agentgateway` and check its `parametersRef`.

## MCP Session / CORS Failures

**Symptom:** a browser-based MCP client (e.g. an inspector) fails with a CORS error or loses its session between calls.

**Causes:**

- Missing `exposeHeaders: ["Mcp-Session-Id"]` in the `cors` policy — browsers won't let JS read the session header without it.
- `mcp.statefulMode: stateful` (the default) requires the client to actually send back the session ID it was given; if the client can't read `Mcp-Session-Id` due to the CORS issue above, session pinning breaks even though the server is behaving correctly.
- For OpenAPI-backed targets that are inherently stateless, confirm `mcp.statefulMode: stateless` is set so agentgateway wraps each call with its own init sequence instead of expecting a real session.

See `references/mcp.md` for the full CORS snippet and session-mode explanation.

## Provider Auth Failures (LLM)

**Symptom:** requests to an `llm.models` entry fail with an auth error from the provider.

**Causes and fixes:**

- API key env var referenced in `params.apiKey` (e.g. `$OPENAI_API_KEY`) isn't actually set in the process environment — verify with `agctl proxy config` (it should show the resolved provider config, redacted) rather than assuming the YAML alone is correct.
- For `azure`, confirm `resourceType` (`openAI`/`foundry`/`aiServices`) matches how the resource was actually provisioned — a Foundry-shaped credential against an `openAI`-typed config (or vice versa) will look like an auth failure but is actually a routing/path mismatch.
- For `bedrock`/AWS-signed backends reached via `backendAuth.aws`, check that `region` and `serviceName` match the target service exactly (`bedrock` vs `bedrock-agentcore` vs `execute-api` produce different SigV4 signatures).
- For `custom` providers, confirm the `formats[]` entry's `type` matches what the upstream actually expects (`completions` vs `messages` vs `responses`) — a mismatched format type can look like an auth failure when it's really a malformed request.

## Config-Model Migration Confusion

**Symptom:** copy-pasted an example from docs/GitHub and it uses `binds`/`listeners`/`routes` nesting, but the user's own working config uses `gateways`/top-level `routes`. Or vice versa — a `llm.port`/`mcp.port` example doesn't match a `llm.gateways`/`mcp.gateways`-based config.

**Cause:** the schema is mid-migration; both forms are valid and currently documented in different places, but they're not interchangeable field-for-field within the same block.

**Fix:** don't merge the two forms in one file. Pick one (prefer the new `gateways`/`routes`/`*.gateways` model for anything new) and translate the whole example rather than splicing fields from both. See `references/config-model.md` for the side-by-side comparison.

## Policy Not Taking Effect (Kubernetes)

**Symptom:** created an `AgentgatewayPolicy` but its behavior isn't observed.

**Causes:**

- `targetRefs`/`targetSelectors`/`sectionName` mismatch — confirm the policy actually resolves to the resource you expect: `kubectl describe agentgatewaypolicy <name>`.
- A more specific policy at a higher merge-precedence level is winning on the same field — see the merge-precedence order in `references/config-model.md` (per-field last-writer-wins at the highest precedence, not a deep merge).
- `backend.ai`/`backend.mcp` policies targeting a plain `Service` instead of an `AgentgatewayBackend` — these two policy types specifically require an `AgentgatewayBackend` target.

## Rate Limiting Not Triggering

```bash
# Confirm the policy is actually attached to the route/gateway you're testing
agctl proxy config | grep -A5 localRateLimit

# For remoteRateLimit, confirm the external rate-limit service is reachable
# from the proxy (not just from your workstation)
```

If limiting by token cost (`type: tokens`) isn't behaving as expected, confirm the traffic is actually LLM traffic with `llm.totalTokens` populated — the default cost expression has nothing to count on non-LLM routes.

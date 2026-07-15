# agentgateway Installation Reference

## Standalone Binary

```bash
# Latest release
curl -sL https://agentgateway.dev/install | bash

# Pin a specific release
curl -sL https://agentgateway.dev/install | bash -s -- --version v1.3.1

agentgateway --version
# {"version":"...","git_revision":"...","rust_version":"...","build_profile":"release","build_target":"..."}
```

Run with a config file (hot-reloaded on change, except the top-level `config:` section):

```bash
agentgateway -f config.yaml
```

Run with **no** `-f` at all: agentgateway bootstraps `~/.config/agentgateway/config.yaml` and starts the admin UI so you can build the whole config from there. Saving from the UI overwrites the file and drops comments, so prefer file-based config once you have something worth keeping under version control.

Nightly/dev builds are pulled from GitHub Actions artifacts rather than the install script:

```bash
gh run download <run-id> -R agentgateway/agentgateway -n release-binary-mac
```

## Docker

```bash
docker run -v "$PWD/config.yaml:/config.yaml" -p 3000:3000 \
  cr.agentgateway.dev/agentgateway:v1.3.1 -f /config.yaml
```

Docker Compose works the same way — pass `command: ["-f", "/config.yaml"]` and mount the config file as a volume.

## From Source

```bash
cargo run -- -f examples/traffic-a2a/config.yaml
```

## Companion CLI (`agctl`)

A separate binary for inspecting a running controller or proxy — install via the "Install agctl" page in the docs. Key subcommands: `agctl proxy config` (dump live config), `agctl proxy trace` (live request tracing), `agctl controller log`, `agctl costs import` (load a cost catalog).

## Admin UI

Default bind is `localhost:15000`, path `/ui/`. To expose beyond localhost:

```yaml
config:
  adminAddr: "0.0.0.0:15000"   # or ip:port | localhost:port | unix:/path | "off"
```

Or via env var: `ADMIN_ADDR=0.0.0.0:15000`. The UI includes an LLM playground (`/ui/llm/playground/`) and an MCP tool playground with an init/session flow. Remember: `config.adminAddr` is in the static-only `config:` section, so changing it requires a restart, not a hot reload.

## Kubernetes

Two Helm charts, both from `oci://cr.agentgateway.dev/charts/...`, plus the upstream Gateway API CRDs:

```bash
# 1. Gateway API CRDs — standard channel
kubectl apply --server-side --force-conflicts \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

# Use the experimental channel instead if you need experimental Gateway API features:
# https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/experimental-install.yaml

export AGENTGATEWAY_VERSION=v1.3.1   # verify the latest release before pinning

# 2. agentgateway CRDs (AgentgatewayBackend, AgentgatewayPolicy, AgentgatewayParameters)
helm upgrade -i agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --create-namespace --namespace agentgateway-system \
  --version ${AGENTGATEWAY_VERSION} \
  --set controller.image.pullPolicy=Always

# 3. agentgateway control plane
helm upgrade -i agentgateway oci://cr.agentgateway.dev/charts/agentgateway \
  --namespace agentgateway-system \
  --version ${AGENTGATEWAY_VERSION} \
  --set controller.image.pullPolicy=Always \
  --wait

# 4. Verify
kubectl get pods -n agentgateway-system
```

Enable experimental Gateway API features on the controller itself (separate from which CRD channel you installed):

```bash
helm upgrade agentgateway ... \
  --set controller.extraEnv.KGW_ENABLE_GATEWAY_API_EXPERIMENTAL_FEATURES=true
```

### Creating a Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: agentgateway-proxy
  namespace: agentgateway-system
spec:
  gatewayClassName: agentgateway
  listeners:
  - protocol: HTTP
    port: 80
    name: http
    allowedRoutes:
      namespaces:
        from: All
```

The `agentgateway` `GatewayClass` (controller name `agentgateway.dev/agentgateway`) auto-provisions a Deployment + Service named after the Gateway (here, `agentgateway-proxy`, container `agent-gateway`) — no separate proxy-deployment step needed.

Nightly/dev chart builds use chart version `0.0.0-latest-dev` with `--set controller.image.pullPolicy=Always`, same as production charts otherwise.

### Uninstall

```bash
helm uninstall agentgateway agentgateway-crds -n agentgateway-system
kubectl delete namespace agentgateway-system
```

## Version Matrix Notes

Check what's actually installed before trusting any example above:

- CLI/binary: `agentgateway --version`
- Kubernetes: `helm list -n agentgateway-system`
- Gateway API CRD channel: inspect installed CRDs directly (`kubectl get crd gateways.gateway.networking.k8s.io -o yaml`) rather than assuming standard v1.5.0 vs experimental v1.6.0 — both appear in current docs depending on the feature being used.

agentgateway is past 1.0 (v1.3.1 at time of writing) but the config schema is mid-migration (see `references/config-model.md` for the `binds` → `gateways`/`routes` deprecation) — always cross-reference <https://github.com/agentgateway/agentgateway/releases> before pinning a version in a manifest or docs example.

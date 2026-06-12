# Workflows

## Install and Bootstrap

Start by identifying the target:

```bash
flux --version
flux check --pre
kubectl version
kubectl get ns flux-system
```

For a new GitOps-managed cluster, prefer provider-specific `flux bootstrap` because it creates the `flux-system` source and reconciliation resources and commits them to Git. Use `flux install --export` only when the repo intentionally vendors Flux install manifests or the platform has a separate bootstrap process.

Pin or record the Flux version being installed. For upgrades, read the release notes for every skipped minor version and check component changelogs linked from the release.

## Repository Structure

Prefer explicit cluster entrypoints:

```text
clusters/
  production/
    flux-system/
    infrastructure/
    apps/
  staging/
    flux-system/
    infrastructure/
    apps/
```

Keep sources near their consumers when ownership is local; centralize shared sources only when multiple Kustomizations or HelmReleases intentionally share them. Use clear `dependsOn` ordering for CRDs, controllers, platform services, and apps. Avoid hidden ordering through path naming alone.

## Authoring Pattern

Source resources fetch artifacts. Reconciliation resources consume artifacts.

- `GitRepository`, `OCIRepository`, `HelmRepository`, `Bucket`: define where artifacts come from.
- `Kustomization`: applies Kubernetes manifests from a source artifact, handles prune, health checks, dependency ordering, and SOPS decryption.
- `HelmRelease`: installs or upgrades charts from `HelmRepository`, `HelmChart`, `OCIRepository`, or other supported sources.
- `Provider`, `Alert`, `Receiver`: define notifications and webhook-driven reconciliation.

Use these defaults unless the repo has a stronger local convention:

```yaml
spec:
  interval: 10m
  timeout: 2m
  prune: true
  wait: true
```

Set `prune: true` for Git-owned resources unless deletion must be manually controlled. Use `suspend: true` for paused reconciliation rather than deleting resources.

## Validation

Validate locally before relying on the controller:

```bash
flux diff kustomization <name> --path ./clusters/<cluster>/<path>
kustomize build ./clusters/<cluster>/<path>
flux-schema validate ./clusters/<cluster>
flux-schema discover ./clusters/<cluster> -o json
```

If `flux-schema` is unavailable, use `kubectl apply --dry-run=server`, `kubectl explain`, and the target CRD schemas from the cluster.

## Reconcile Intentionally

After Git changes land:

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
flux get all -A
```

Use `--with-source` when the source revision should be refreshed immediately.

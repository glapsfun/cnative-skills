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

## Upgrading Flux

Migrate API versions before upgrading the CRDs. Since Flux 2.9 every Flux CRD serves exactly one API version, so manifests in Git or objects in etcd still on a removed version break the upgrade. Removals: 2.7 dropped every `v1beta1` (and `helm.toolkit.fluxcd.io/v2beta1`); 2.8 dropped `source.toolkit.fluxcd.io/v1beta2`, `kustomize.toolkit.fluxcd.io/v1beta2`, and `helm.toolkit.fluxcd.io/v2beta2`; 2.9 dropped `image.toolkit.fluxcd.io/v1beta2` and `notification.toolkit.fluxcd.io/v1beta2`.

Current API versions (Flux 2.9):

| Kind | apiVersion |
|------|------------|
| `GitRepository`, `OCIRepository`, `HelmRepository`, `HelmChart`, `Bucket`, `ExternalArtifact` | `source.toolkit.fluxcd.io/v1` |
| `Kustomization` | `kustomize.toolkit.fluxcd.io/v1` |
| `HelmRelease` | `helm.toolkit.fluxcd.io/v2` |
| `Receiver` | `notification.toolkit.fluxcd.io/v1` |
| `Alert`, `Provider` | `notification.toolkit.fluxcd.io/v1beta3` (still beta; there is no v1) |
| `ImageRepository`, `ImagePolicy`, `ImageUpdateAutomation` | `image.toolkit.fluxcd.io/v1` |
| `ArtifactGenerator` | `source.extensions.fluxcd.io/v1beta1` |

Upgrade order from 2.7 or 2.8 (both already serve every version in the table):

```bash
flux migrate -f . --dry-run   # preview API rewrites in the Git checkout
flux migrate -f .             # rewrite manifests in Git, then commit and push
flux migrate                  # cluster mode: migrates objects stored in etcd; cluster-admin, mutates the cluster, confirm first
# upgrade Flux (flux bootstrap or flux install), then run `flux migrate` once more
```

From 2.6 or older, the 2.6 cluster cannot serve the image `v1` APIs, so do not migrate Git straight to the latest versions: follow the upstream procedure (<https://github.com/fluxcd/flux2/discussions/5572>), which migrates Git with `flux migrate -v 2.6 -f .`, runs cluster-mode `flux migrate`, upgrades, then migrates the image APIs with `flux migrate -v 2.8 -f .` and reruns `flux migrate`. With Flux Operator v0.53.0+, the operator runs the cluster-mode migration itself; the Git migration is still yours. Target v2.9.5 as the minimum 2.9 patch (v2.9.4 fixes GHSA-mwcp-qpcg-fr7c, see `security-validation.md`). Flux 2.9 supports Kubernetes 1.34–1.36, but `flux check --pre` still passes on 1.33, so compare `kubectl version` with the release notes yourself. Flux supports its last three minors (2.9, 2.8, 2.7), and the CLI and controllers should be within one minor of each other. After the upgrade, read "After Upgrading to 2.9" in `troubleshooting.md` for defaults that changed.

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
flux diff kustomization <name> --path ./clusters/<cluster>/<path> --strict-substitute   # fail on unset ${var}, as 2.9 controllers do
kustomize build ./clusters/<cluster>/<path>
kustomize build ./clusters/<cluster>/<path> | flux envsubst --strict   # the same strict check offline (no cluster)
flux plugin install schema        # once per machine (Flux CLI 2.9+)
flux schema validate ./clusters/<cluster>
flux schema discover ./clusters/<cluster> -o json
```

Flux Schema ships as a Flux CLI plugin since 2.9. `flux plugin install` puts the `flux-schema` binary in `~/.fluxcd/plugins/` (override with `FLUXCD_PLUGINS`), which is not on `PATH`, so call it as `flux schema`; a standalone `flux-schema` binary you placed on `PATH` takes the same subcommands. In CI, pin the plugin: `flux plugin install schema@<version>` (or `@sha256:<digest>`), or `fluxcd/flux2/action` with `plugins: schema@<version>`.

If neither `flux schema` nor a standalone `flux-schema` is available, use `kubectl apply --dry-run=server`, `kubectl explain`, and the target CRD schemas from the cluster.

## Reconcile Intentionally

After Git changes land:

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
flux get all -A
```

Use `--with-source` when the source revision should be refreshed immediately.

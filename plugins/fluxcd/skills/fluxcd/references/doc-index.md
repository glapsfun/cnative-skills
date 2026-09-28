# Documentation Index

Use this when a task requires exact official documentation paths. Refresh with:

```bash
bash scripts/fluxcd-doc-discover.sh
```

## Website Sections

Official rendered docs live at <https://fluxcd.io/flux/> and source lives under `fluxcd/website/content/en/flux/`.

High-value areas:

- `get-started.md` and `installation/`: bootstrap and installation flows.
- `concepts.md`: source, reconciliation, desired state, and GitOps Toolkit concepts.
- `components/source/`: `GitRepository`, `OCIRepository`, `HelmRepository`, `HelmChart`, `Bucket`, `ExternalArtifact`, `ArtifactGenerator`.
- `components/kustomize/`: `Kustomization`, health checks, dependencies, prune, decryption, drift.
- `components/helm/`: `HelmRelease` and Helm remediation behavior.
- `components/notification/`: `Provider`, `Alert`, `Receiver`, webhook events.
- `components/image/`: image reflector and image automation resources.
- `guides/`: repository structure, SOPS, notifications, receivers, Helm releases, image updates.
- `security/`: SLSA, security posture, and release verification.
- `monitoring/`: metrics, alerts, dashboards, and operational observability.
- `releases/`: supported versions and upgrade notes.
- `cmd/`: Flux CLI command reference.
- `faq.md`: practical failure modes and behavior clarifications.

## Controller API and CRD Sources

When field-level accuracy matters, use the target cluster CRDs first. If cluster access is unavailable, use controller repos:

- `fluxcd/source-controller`: `docs/spec/v1/*.md` and `config/crd/bases/*.yaml`
- `fluxcd/kustomize-controller`: `docs/spec/v1/kustomizations.md` and `config/crd/bases/kustomize.toolkit.fluxcd.io_kustomizations.yaml`
- `fluxcd/helm-controller`: `docs/spec/v2/helmreleases.md` and `config/crd/bases/helm.toolkit.fluxcd.io_helmreleases.yaml`
- `fluxcd/notification-controller`: `docs/spec/v1/receivers.md`, `docs/spec/v1beta3/` (Alert, Provider), and `config/crd/bases/notification.toolkit.fluxcd.io_*.yaml`
- `fluxcd/image-reflector-controller` and `fluxcd/image-automation-controller`: `docs/spec/v1/*.md` and `config/crd/bases/*.yaml`
- `fluxcd/source-watcher`: `docs/spec/v1beta1/artifactgenerators.md` and `config/crd/bases/*.yaml`

Read the served API version from `config/crd/bases` at the controller tag that matches the target Flux release: the `api/` Go packages still contain older versions that the CRDs no longer serve.

Flux release assets also include `install.yaml`, `manifests.tar.gz`, and `crd-schemas.tar.gz`.

## Validation Sources

- `fluxcd/flux-schema/README.md` and <https://fluxcd.io/flux/cli-plugins/flux-schema/>: install as the `schema` Flux CLI plugin and run `flux schema validate|discover`.
- `fluxcd/flux-schema/docs/manifests-validation.md`: local and CI validation.
- `fluxcd/flux-schema/docs/repo-discovery.md`: repository inventory for audits.
- `fluxcd/flux-schema/docs/config.md`: `.fluxschema.yml` config.
- `fluxcd/flux-schema/catalog/README.md`: built-in schema catalog coverage.

## Official Agent Skills

Use the official Flux agent skills as additional comparison material, not as a substitute for live cluster evidence (they prefer `flux schema`, so install the `schema` plugin; they fall back to a `flux-schema` binary on `PATH`):

- `fluxcd/agent-skills/skills/gitops-knowledge`
- `fluxcd/agent-skills/skills/gitops-repo-audit`
- `fluxcd/agent-skills/skills/gitops-cluster-debug`

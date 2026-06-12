# Documentation Index

Use this when a task requires exact official documentation paths. Refresh with:

```bash
bash scripts/fluxcd-doc-discover.sh
```

## Website Sections

Official rendered docs live at https://fluxcd.io/flux/ and source lives under `fluxcd/website/content/en/flux/`.

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

- `fluxcd/source-controller/api/v1/*_types.go` and `config/crd/bases/*.yaml`
- `fluxcd/kustomize-controller/api/v1/kustomization_types.go` and `config/crd/bases/kustomize.toolkit.fluxcd.io_kustomizations.yaml`
- `fluxcd/notification-controller/api/v1*/` and `config/crd/bases/notification.toolkit.fluxcd.io_*.yaml`

Flux release assets also include `install.yaml`, `manifests.tar.gz`, and `crd-schemas.tar.gz`.

## Validation Sources

- `fluxcd/flux-schema/docs/guides/manifests-validation.md`: local and CI validation.
- `fluxcd/flux-schema/docs/guides/repo-discovery.md`: repository inventory for audits.
- `fluxcd/flux-schema/docs/config/README.md`: `.fluxschema.yml` config.
- `fluxcd/flux-schema/catalog/README.md`: built-in schema catalog coverage.

## Official Agent Skills

Use the official Flux agent skills as additional comparison material, not as a substitute for live cluster evidence:

- `fluxcd/agent-skills/skills/gitops-knowledge`
- `fluxcd/agent-skills/skills/gitops-repo-audit`
- `fluxcd/agent-skills/skills/gitops-cluster-debug`

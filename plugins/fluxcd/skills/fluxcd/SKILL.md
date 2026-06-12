---
name: fluxcd
description: Flux CD GitOps operator guidance for Kubernetes. Use when Codex needs to explain Flux concepts, plan or review GitOps repository structure, install or bootstrap Flux, author or validate Flux resources, secure Flux with SOPS/RBAC/supply-chain controls, operate Flux controllers, upgrade Flux by version, or troubleshoot Flux reconciliation, source, kustomize, Helm, notification, webhook, and drift issues.
---

# FluxCD

Use this skill to work with Flux CD as a versioned Kubernetes GitOps system. Treat Flux behavior as version-sensitive: check the target cluster or repository version before giving operational advice, and check current upstream release notes when the answer depends on recent Flux behavior.

## First Step

Run or adapt the version helper before making version-specific claims:

```bash
bash scripts/fluxcd-version-check.sh
```

If the user provides a Flux version, cluster output, `gotk-components.yaml`, `install.yaml`, Helm chart version, or controller image tag, use that as the target version and compare it with the latest upstream release. If no version is known, say the advice is based on the latest release detected by the helper and recommend verifying against the cluster.

## Task Routing

- **Explain concepts or choose an approach**: read `references/official-sources.md`, then describe Flux as sources, reconcilers, artifacts, desired state, and status conditions.
- **Install, bootstrap, or structure GitOps repos**: read `references/workflows.md`; prefer `flux bootstrap` for new GitOps-managed clusters and exported manifests only when the repo explicitly manages installation artifacts.
- **Author or review manifests**: read `references/workflows.md` and `references/security-validation.md`; validate `GitRepository`, `OCIRepository`, `Kustomization`, `HelmRelease`, `Provider`, `Alert`, and `Receiver` resources against the API docs or schemas for the target Flux version.
- **Security work**: read `references/security-validation.md`; cover SOPS, least-privilege service accounts, source verification, network and secret boundaries, image/provenance verification, and tenant isolation.
- **Troubleshooting or operations**: read `references/troubleshooting.md`; collect `flux check`, `flux get ... -A`, events, controller logs, source artifacts, conditions, and recent Git/OCI/Helm revisions before proposing fixes.
- **Documentation or API discovery**: read `references/doc-index.md` or run `bash scripts/fluxcd-doc-discover.sh` to refresh official docs and CRD/API paths.
- **New upstream release appears**: rerun the helper, inspect Flux release notes and component changelogs, then update only the affected reference notes or commands.

## Operating Rules

Prefer official Flux sources over blog posts or stale generated examples. Use `fluxcd.io/flux/`, `fluxcd/flux2`, component controller repos, `fluxcd/flux-schema`, and `fluxcd/agent-skills` as primary sources.

Do not invent CRD fields. When field-level accuracy matters, check the live CRD (`kubectl explain`, `kubectl get crd ... -o yaml`), Flux schema docs, or the controller API spec for the target version.

Separate GitOps desired state from emergency cluster mutations. For persistent fixes, patch the Git repository and reconcile. Use direct `kubectl` changes only for diagnosis or explicitly temporary recovery.

When troubleshooting, follow source-to-apply order: source-controller artifact readiness, then kustomize/helm reconciliation, then workload health and notifications.

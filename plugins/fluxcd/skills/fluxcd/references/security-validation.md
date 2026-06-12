# Security and Validation

## Baseline Checks

Start with version and cluster capability checks:

```bash
bash scripts/fluxcd-version-check.sh
flux check
kubectl auth can-i --list -n flux-system
```

Check the release notes for security fixes. For the 2026-06-12 baseline, Flux `v2.8.8` included CVE fixes through `go-git v5.19.1` in source-related components.

## Secrets

Prefer SOPS-encrypted Kubernetes Secrets committed to Git, decrypted by kustomize-controller using the configured age, PGP, cloud KMS, or workload identity path. Keep decryption keys out of application namespaces unless tenant isolation requires scoped keys.

Do not commit plaintext credentials, bootstrap tokens, deploy keys, webhook secrets, or cloud credentials. For Git authentication, scope tokens or deploy keys to the minimal repo access needed by source-controller.

## RBAC and Tenancy

Use Flux service accounts and impersonation for tenant workloads:

- Set `spec.serviceAccountName` on tenant `Kustomization` and `HelmRelease` resources.
- Bind only the verbs and namespaces required by that tenant.
- Keep cluster-admin reconciliation for platform-owned bootstrap layers only when required.
- Separate platform, tenant, and app namespaces in Git and Kubernetes.

## Supply Chain

For Git sources, prefer signed commits or protected branches where the organization supports them. For OCI sources and artifacts, check the source-controller support for Cosign or Notation verification in the target Flux version. Pin image/chart versions or semver ranges intentionally; avoid floating `latest` for production.

Verify Flux installation artifacts by using official release assets, checksums, provenance, or the official install path. Do not copy random manifests from third-party tutorials into production bootstrap.

## Network and Runtime

Review network egress requirements for source-controller and notification-controller. Restrict egress when your cluster policy supports it, but allow required Git, OCI, Helm, bucket, and webhook endpoints.

Monitor controller resource usage and logs. During upgrades, watch source-controller and helm-controller carefully because source fetches and chart rendering are common pressure points.

## Policy and CI

Shift validation left:

```bash
flux-schema validate ./clusters
flux-schema discover ./clusters -o json
conftest test ./clusters
```

Use policy checks for namespace boundaries, forbidden plaintext Secrets, missing `serviceAccountName`, unpinned images, disabled prune, and unsupported API versions.

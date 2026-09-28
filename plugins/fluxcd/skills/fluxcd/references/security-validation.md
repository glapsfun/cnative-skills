# Security and Validation

## Baseline Checks

Start with version and cluster capability checks:

```bash
bash scripts/fluxcd-version-check.sh
flux check
kubectl auth can-i --list -n flux-system
```

Check the release notes and advisories (<https://github.com/fluxcd/flux2/security/advisories>) for security fixes. For the 2026-09-28 baseline:

- **GHSA-mwcp-qpcg-fr7c (high, fixed in v2.9.4):** the CLI-installed `allow-webhooks` NetworkPolicy admitted traffic to notification-controller from every namespace on all ports, so any pod could reach the event server (port 9090) and forge Flux events, alerts, and commit statuses. From v2.9.4 the policy allows only TCP 9292 (the Receiver port). There is no 2.7.x or 2.8.x backport: on 2.7, 2.8, or 2.9.0–2.9.3, patch the policy with `ports: [{protocol: TCP, port: 9292}]` as a bootstrap customization (the upstream workaround assumes a `flux bootstrap` install).
- Source components still carry `go-git v5.19.1` (CVE fixes since v2.8.8), and v2.8.8 (source-controller v1.8.5) also fixed the source-controller path traversal CVE-2026-47680.

## Secrets

Prefer SOPS-encrypted Kubernetes Secrets committed to Git, decrypted by kustomize-controller using the configured age, PGP, cloud KMS, or workload identity path. Since 2.9, kustomize-controller can also log in to Vault or OpenBao with a Kubernetes ServiceAccount token instead of a static `sops.vault-token` (controller flag `--sops-vault-configmap=<name>`, whose ConfigMap also allowlists the Vault addresses). Keep decryption keys out of application namespaces unless tenant isolation requires scoped keys.

Do not commit plaintext credentials, bootstrap tokens, deploy keys, webhook secrets, or cloud credentials. For Git authentication, scope tokens or deploy keys to the minimal repo access needed by source-controller.

## RBAC and Tenancy

Use Flux service accounts and impersonation for tenant workloads:

- Set `spec.serviceAccountName` on tenant `Kustomization` and `HelmRelease` resources.
- Bind only the verbs and namespaces required by that tenant.
- Keep cluster-admin reconciliation for platform-owned bootstrap layers only when required.
- Separate platform, tenant, and app namespaces in Git and Kubernetes.

## Supply Chain

For Git sources, prefer signed commits or protected branches where the organization supports them, and enforce signatures with `GitRepository` `.spec.verify` (mode `HEAD`, `Tag`, or `TagAndHEAD`). The verify Secret holds PGP keys as `*.asc` and, since 2.9, SSH public keys as `*.sshpub`. Commits pushed by ImageUpdateAutomation can be SSH-signed (`.spec.git.commit.signingKey.type: ssh`), and `flux bootstrap` takes `--ssh-signing-key-file`. For OCI sources and artifacts, check the source-controller support for Cosign or Notation verification in the target Flux version. For keyless Cosign against a self-hosted or air-gapped Sigstore, `OCIRepository` `.spec.verify.trustedRootSecretRef` (2.9+) points to a Secret with a `trusted_root.json` from `cosign trusted-root create`. Pin image/chart versions or semver ranges intentionally; avoid floating `latest` for production.

Verify Flux installation artifacts by using official release assets, checksums, provenance, or the official install path. Do not copy random manifests from third-party tutorials into production bootstrap.

## Network and Runtime

Review network egress requirements for source-controller and notification-controller, and confirm the `allow-webhooks` NetworkPolicy exposes only port 9292 (see GHSA-mwcp-qpcg-fr7c above). For `Receiver`s called from CI jobs that can mint OIDC ID tokens (GitHub Actions, Forgejo), the secret-less `type: generic-oidc` (2.9+) validates a bearer token against `.spec.oidcProviders` with CEL rules instead of a shared token. It does not replace the typed GitHub, GitLab, or registry receivers. Public issuers mint tokens for any caller on the platform, and the webhook path is derived only from name and namespace, so the CEL `validations` are the only gate: pin identity claims such as `repository_owner` and `repository`. Restrict egress when your cluster policy supports it, but allow required Git, OCI, Helm, bucket, and webhook endpoints.

Monitor controller resource usage and logs. During upgrades, watch source-controller and helm-controller carefully because source fetches and chart rendering are common pressure points.

## Policy and CI

Shift validation left:

```bash
flux schema validate ./clusters          # schema plugin: flux plugin install schema
flux schema discover ./clusters -o json
conftest test ./clusters
```

Use policy checks for namespace boundaries, forbidden plaintext Secrets, missing `serviceAccountName`, unpinned images, disabled prune, and unsupported API versions.

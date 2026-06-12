# Troubleshooting

## Triage Order

1. Check Flux and Kubernetes versions.
2. Check source readiness and artifact revision.
3. Check reconciliation resource conditions.
4. Check controller logs and Kubernetes events.
5. Compare desired state in Git with rendered manifests and live cluster state.

## Core Commands

```bash
flux check
flux get all -A
flux get sources git -A
flux get sources oci -A
flux get kustomizations -A
flux get helmreleases -A
flux events -A
kubectl -n flux-system get pods,deploy
```

For a specific object:

```bash
flux tree kustomization <name> -n <namespace>
flux trace kustomization <name> -n <namespace>
flux reconcile source git <name> -n <namespace>
flux reconcile kustomization <name> -n <namespace> --with-source
kubectl describe kustomization <name> -n <namespace>
```

Controller logs:

```bash
kubectl -n flux-system logs deploy/source-controller --since=30m
kubectl -n flux-system logs deploy/kustomize-controller --since=30m
kubectl -n flux-system logs deploy/helm-controller --since=30m
kubectl -n flux-system logs deploy/notification-controller --since=30m
```

## Common Failure Classes

- **Source not ready**: bad URL, missing credentials, host key mismatch, branch/tag/path missing, OCI auth error, Helm repository index failure, bucket permission error, webhook secret mismatch.
- **Artifact ready but apply fails**: invalid YAML, unknown CRD, wrong API version, server-side dry-run error, immutable field change, namespace missing, RBAC denial, SOPS decryption failure.
- **Health check timeout**: deployment unavailable, CRD controller not ready, wrong `dependsOn`, insufficient timeout, app-level rollout issue.
- **Helm failure**: chart version not found, values schema error, hook failure, CRD ownership conflict, release name too long, remediation loop.
- **Prune/drift surprise**: resource moved paths without inventory continuity, resource excluded from Git, ownership conflict, `prune` setting mismatch.
- **Notifications missing**: Provider secret invalid, Alert selector mismatch, event severity mismatch, Receiver ingress or webhook secret issue.

## Evidence to Ask For

Ask for the smallest useful bundle:

```bash
flux version
flux check
flux get all -A
flux events -A --since=1h
kubectl -n flux-system get deploy -o wide
kubectl -n flux-system logs deploy/<controller> --since=30m
kubectl get <kind> <name> -n <namespace> -o yaml
```

If the issue is repo-specific, inspect the exact Git path referenced by `spec.path` and the source revision shown in status.

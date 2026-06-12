# Versioning & Official Sources

Use the live cluster first. `kubectl explain`, `kubectl api-resources`, and server-side dry-run are generated from the connected API server and override any static reference in this skill.

## Baseline snapshot

- Snapshot date: 2026-06-12.
- Kubernetes docs baseline: v1.36.
- Helm docs baseline: v4.2.0.
- GitOps docs baseline: current Flux docs and Argo CD stable docs available on the snapshot date.

If upstream versions differ, inspect release notes and generated API docs before giving field-level advice.

## Refresh checklist

```bash
scripts/k8s-context-check.sh
kubectl version
kubectl api-resources
kubectl explain <type>.<field> --recursive
helm version
flux check
argocd version --client
```

## Primary sources

- Kubernetes kubectl reference: https://kubernetes.io/docs/reference/kubectl/
- Kubernetes generated kubectl commands: https://kubernetes.io/docs/reference/kubectl/generated/
- Kubernetes debugging: https://kubernetes.io/docs/tasks/debug/
- Pod debugging: https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/
- Services and EndpointSlices: https://kubernetes.io/docs/concepts/services-networking/service/
- NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- PersistentVolumes: https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Server-Side Apply: https://kubernetes.io/docs/reference/using-api/server-side-apply/
- Node drain: https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/
- Helm command docs: https://helm.sh/docs/helm/
- Helm chart template guide: https://helm.sh/docs/chart_template_guide/
- Flux troubleshooting: https://fluxcd.io/flux/cheatsheets/troubleshooting/
- Argo CD user guide: https://argo-cd.readthedocs.io/en/stable/user-guide/

## Answering rule

When the question depends on an exact field, default, API version, admission rule, or command flag:

1. Prefer the live cluster or local CLI help.
2. If unavailable, state the baseline version used.
3. Link or name the official source category when giving version-sensitive guidance.
4. Avoid advice copied from old blog posts, Stack Overflow answers, or cloud-provider docs unless the task is provider-specific.

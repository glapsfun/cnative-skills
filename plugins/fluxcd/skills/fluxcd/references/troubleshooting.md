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
kubectl get fluxcd -A          # every Flux object via the CRD category (Flux 2.9+)
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
- **Helm failure**: chart version not found, values schema error, hook failure, CRD ownership conflict, release name too long, remediation loop. helm-controller embeds Helm v4 since Flux 2.8: new HelmReleases use server-side apply and kstatus waits (`.spec.waitStrategy.name: poller`), so field-manager conflicts and waits on custom resources are new failure sources.
- **Prune/drift surprise**: resource moved paths without inventory continuity, resource excluded from Git, ownership conflict, `prune` setting mismatch. For a field another controller owns (an HPA scaling `replicas`, a webhook injecting CA bundles), add a Kustomization ignore rule (Flux 2.9+) instead of removing the object from Git: `spec.ignore: [{paths: ["/spec/replicas"], target: {kind: Deployment}}]` (JSON Pointer paths; without `target` the rule matches every object). `flux diff kustomization` honours the rules.
- **Notifications missing**: Provider secret invalid, Alert selector mismatch, event severity mismatch, Receiver ingress or webhook secret issue.

## After Upgrading to 2.9

Flux 2.9 changed defaults that make previously working objects fail. Check these first when a reconcile breaks right after an upgrade:

| Symptom | Cause and fix |
|---------|---------------|
| Kustomization fails on a `${var}` that used to render empty | `StrictPostBuildSubstitutions` is on by default: a variable without a default that is missing from `substitute`/`substituteFrom` now fails. Add the variable, give it a default (`${var:=default}`), or set `.spec.postBuild.substituteStrategy`. Reproduce locally with `flux diff kustomization ... --strict-substitute`. |
| HelmRelease post-renderer patches now change chart hooks | `.spec.postRenderStrategy` defaults to `combined` (hooks and templates together, the Helm 4 default). Set `postRenderStrategy: nohooks` for the Helm 3 behaviour, or enable the helm-controller `UseHelm3Defaults` feature gate cluster-wide (it also restores the client-side apply and legacy wait defaults). |
| Object stuck on `image.toolkit.fluxcd.io/v1beta2` or `notification.toolkit.fluxcd.io/v1beta2` | Those versions were removed; run `flux migrate -f .` on Git and `flux migrate` on the cluster (see "Upgrading Flux" in `workflows.md`). |
| GCR `Receiver` stops authenticating | Its Secret now needs `email` (the Pub/Sub push service account) and `audience` next to `token`; regenerate it with `flux create secret receiver --type=gcr --email-claim=... --export`. |
| Remote-cluster Kustomization or HelmRelease rejects its kubeconfig (2.9.5+) | Kubeconfigs in `.spec.kubeConfig.secretRef` must embed credentials (`token`, `*-data` fields); file references such as `tokenFile` or `certificate-authority` are rejected. |
| ImageUpdateAutomation push refused (2.9.4+) | `.spec.git.push.refspec` no longer accepts force (`+...`) or delete refspecs. |

## Evidence to Ask For

Ask for the smallest useful bundle:

```bash
flux version
flux check
flux get all -A
flux events -A                 # no --since flag; narrow with --for <Kind>/<name> or --types Warning
kubectl -n flux-system get deploy -o wide
kubectl -n flux-system logs deploy/<controller> --since=30m
kubectl get <kind> <name> -n <namespace> -o yaml
```

If the issue is repo-specific, inspect the exact Git path referenced by `spec.path` and the source revision shown in status.

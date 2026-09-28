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
- **Helm failure**: chart version not found, values schema error, hook failure, CRD ownership conflict, release name too long, remediation loop. helm-controller embeds Helm v4 since Flux 2.8: new HelmReleases use server-side apply (existing ones keep their last apply method), and every HelmRelease now waits with kstatus (`.spec.waitStrategy.name` defaults to `poller`). Field-manager conflicts and waits on custom resources are new failure sources; set `.spec.waitStrategy.name: legacy`, or enable `UseHelm3Defaults`, if an existing release starts timing out after the upgrade.
- **Prune/drift surprise**: resource moved paths without inventory continuity, resource excluded from Git, ownership conflict, `prune` setting mismatch. For a field another controller owns (an HPA scaling `replicas`, a webhook injecting CA bundles), add a Kustomization ignore rule (Flux 2.9+) instead of removing the field from Git (on 2.7 and 2.8, omitting the field is the only fix): `spec.ignore: [{paths: ["/spec/replicas"], target: {kind: Deployment}}]` (JSON Pointer paths; without `target` the rule matches every object). `flux diff kustomization` honours the rules.
- **Notifications missing**: Provider secret invalid, Alert selector mismatch, event severity mismatch, Receiver ingress or webhook secret issue.

## After Upgrading to 2.9

Flux 2.9 changed defaults that make previously working objects fail. Check these first when a reconcile breaks right after an upgrade:

| Symptom | Cause and fix |
|---------|---------------|
| Kustomization fails on a `${var}` that used to render empty | `StrictPostBuildSubstitutions` is on by default: when post-build substitution runs, a variable without a default that is missing from `substitute`/`substituteFrom` now fails. Add the variable, give it a default (`${var:=}` for an empty default), escape a literal as `$${var}`, or exclude the object with the label or annotation `kustomize.toolkit.fluxcd.io/substitute: disabled`. The cluster-wide opt-out is `--feature-gates=StrictPostBuildSubstitutions=false` on kustomize-controller. Check offline with `kustomize build <path> \| flux envsubst --strict`; `flux diff kustomization --strict-substitute` does the same against the cluster. |
| HelmRelease post-renderer patches now change chart hooks | `.spec.postRenderStrategy` defaults to `combined` (hooks and templates together, the Helm 4 default). Set `postRenderStrategy: nohooks` for the Helm 3 behaviour, or enable the helm-controller `UseHelm3Defaults` feature gate cluster-wide (it also restores the client-side apply and legacy wait defaults). |
| Object stuck on `image.toolkit.fluxcd.io/v1beta2` or `notification.toolkit.fluxcd.io/v1beta2` | Those versions were removed; run `flux migrate -f .` on Git and `flux migrate` on the cluster (see "Upgrading Flux" in `workflows.md`). |
| GCR `Receiver` stops authenticating | Its Secret now needs `email` (the Pub/Sub push service account) and `audience` (by default the full push URL, `https://<host><.status.webhookPath>`) next to `token`. Add the two keys to the existing Secret. Do not regenerate it without `--token=<existing token> --hostname=<host>`: `flux create secret receiver` otherwise mints a new token, which changes `.status.webhookPath` and breaks the Pub/Sub subscription. Its `--export` output is a plaintext Secret, so SOPS-encrypt it before committing. |
| Remote-cluster Kustomization or HelmRelease rejects its kubeconfig (2.9.5+) | Kubeconfigs in `.spec.kubeConfig.secretRef` must embed credentials (`token`, `*-data` fields); file references such as `tokenFile` or `certificate-authority` are rejected. |
| ImageUpdateAutomation rejected on apply, or its refspec push refused (2.9.4+) | The CRD now rejects force (`+...`) and delete (`:refs/heads/x`) refspecs in `.spec.git.push.refspec`, and refspec pushes no longer inherit force, so a non-fast-forward push fails. |

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

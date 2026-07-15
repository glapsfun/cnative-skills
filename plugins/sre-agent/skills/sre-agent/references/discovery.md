# Environment and Observability Discovery

Phase 2 playbook. Run `scripts/sre-env-discovery.sh` and
`scripts/sre-obs-discovery.sh` first; use this file to interpret their output
and to go deeper manually when a section comes back empty or ambiguous.
Everything here is read-only.

## Interpreting sre-env-discovery.sh output

The script prints six sections. For each finding, take the follow-up action:

| Section | Finding | Follow-up |
| :--- | :--- | :--- |
| `## Tooling` | `missing kubectl` | No cluster inspection possible — switch to the repo-only fallback below |
| `## Tooling` | `missing flux`/`missing argocd` | GitOps CRDs may still exist; the GitOps section checks CRDs independently of CLIs |
| `## Kubernetes` | `no current context configured` | Ask the user which cluster/kubeconfig to use — never pick one for them |
| `## Kubernetes` | `cannot list namespaces (limited RBAC)` | Ask the user for the target namespace and scope every later command with `-n` |
| `## Kubernetes` | node provider hint (`aws:///…`, `gce://…`, `azure://…`) | Confirms the cloud even when no cloud CLI is authenticated |
| `## EKS` | `EKS: detected` | Dispatch `sre-eks-investigator` unconditionally this run, regardless of symptom shape |
| `## EKS` | `EKS: not detected` or `Skipped (no cluster access)` | Skip the EKS investigator |
| `## GKE` | `GKE: detected` | Dispatch `sre-gke-investigator` unconditionally this run, regardless of symptom shape |
| `## GKE` | `GKE: not detected` or `Skipped (no cluster access)` | Skip the GKE investigator |
| `## GitOps` | `Flux CRDs present` | Run `flux get kustomizations -A` and `flux get helmreleases -A` to find who manages the target |
| `## GitOps` | `Argo CD CRDs present` | Run `kubectl get applications -A` to find the managing Application |
| `## Cloud` | CLI present but `not authenticated` | Cloud evidence is unavailable; record it in the ledger under Missing |

## Interpreting sre-obs-discovery.sh output

| Section | Finding | Follow-up |
| :--- | :--- | :--- |
| `## Prometheus` | one or more services | Port-forward with the printed command, then run the readiness probe and the API smoke test below |
| `## Prometheus` | `not found` | Check for managed alternatives: Grafana Cloud/Mimir (agent remote-write — look for `alloy`/`grafana-agent` pods), or cloud-native metrics (CloudWatch Container Insights, GCP Managed Prometheus) |
| `## Alertmanager` | found | Query active alerts (see `prometheus-analysis.md`) and correlate their start times with the incident |
| `## Grafana` | found | Use `grafana-discovery.md` to mine dashboards for the app's real metric names |
| `## Loki` | found | Use `logs-investigation.md` LogQL patterns |
| `## Loki` | `not found` | Fall back to Elasticsearch/OpenSearch (`elk-investigation.md`), else `kubectl logs` |
| `## Mimir` | found | Long-term Prometheus store — query it exactly like Prometheus (`/prometheus/api/v1/...`); see `prometheus-analysis.md` |
| `## Tempo` | found | Latency/error incident? Dispatch `sre-trace-analyst` with the endpoint (see `tracing-investigation.md`) |
| `## Jaeger` | found | Same as Tempo — dispatch `sre-trace-analyst`; Jaeger API timestamps are microseconds |
| `## Elasticsearch/OpenSearch` | found | Use `elk-investigation.md` for the logs path; expect auth — get an API key or Secret name from the user |
| `## Service mesh` | Istio/Linkerd detected | Record in environment map; k8s-investigator collects mesh facts (`mesh-investigation.md`) |
| `## k6` | CLI or operator present | Load validation available for Phase 6 (`load-validation.md`) |
| `## Ingresses` | hosts listed | Prefer in-cluster port-forward for queries; Ingress URLs may require auth you don't have |

## Well-known observability locations

Service-name patterns and default ports the discovery script probes. When
searching manually, these are the names to look for:

| Component | Common service names | Port | Common namespaces |
| :--- | :--- | :--- | :--- |
| Prometheus | `prometheus-server`, `prometheus-k8s`, `prometheus-operated`, `<release>-kube-prometheus-st-prometheus` | 9090 | `monitoring`, `observability`, `prometheus` |
| Alertmanager | `alertmanager`, `alertmanager-operated`, `<release>-kube-prometheus-st-alertmanager` | 9093 | `monitoring`, `observability` |
| Grafana | `grafana`, `<release>-grafana` | 3000 (or 80) | `monitoring`, `observability`, `grafana` |
| Loki | `loki`, `loki-gateway`, `loki-read` | 3100 | `monitoring`, `observability`, `loki` |
| Mimir | `mimir-nginx`, `mimir-gateway` | 9009 | `mimir`, `monitoring` |
| Tempo | `tempo`, `tempo-gateway` | 3200 | `tempo`, `monitoring` |
| Jaeger (query) | `jaeger-query`, `jaeger` | 16686 | `observability`, `monitoring`, `jaeger` |
| Elasticsearch/OpenSearch | `elasticsearch`, `elasticsearch-master`, `opensearch` | 9200 | `elastic`, `logging`, `observability` |

## Access patterns

Port-forward (leave running in the background while querying):

```bash
kubectl port-forward -n <ns> svc/<name> 9090:9090
```

Readiness probes per component:

```bash
curl -fsS localhost:9090/-/ready        # Prometheus
curl -fsS localhost:9093/-/ready        # Alertmanager
curl -fsS localhost:3000/api/health     # Grafana
curl -fsS localhost:3100/ready          # Loki
curl -fsS localhost:3200/ready          # Tempo
curl -fsS localhost:16686/              # Jaeger query UI
curl -fsS localhost:9200/_cluster/health # Elasticsearch/OpenSearch (may 401)
```

Prometheus API smoke test (proves queries will work):

```bash
curl -fsS 'localhost:9090/api/v1/query?query=up' | head -c 400
```

Grafana API calls need a token: `-H "Authorization: Bearer $GRAFANA_TOKEN"`.
The token comes from the user or from a Secret **name** they point you at —
never print secret values. Anonymous read access sometimes works in dev.

External URLs: `kubectl get ingress -A` (and `kubectl get httproutes -A` on
Gateway API clusters) shows externally-exposed observability hosts. Prefer
port-forward — Ingress endpoints often sit behind SSO you cannot pass.

## Detecting the GitOps manager

Cluster-wide:

```bash
kubectl get kustomizations,helmreleases -A   # Flux (or: flux get all -A)
kubectl get applications -A                  # Argo CD (usually -n argocd)
```

Per-object ownership — who manages this specific Deployment:

```bash
kubectl get deploy <name> -n <ns> --show-managed-fields=true -o jsonpath='{.metadata.managedFields[*].manager}'
kubectl get deploy <name> -n <ns> -o jsonpath='{.metadata.labels}'
```

`--show-managed-fields=true` is required — `kubectl` hides managed fields by
default since Kubernetes 1.21, so the first command returns empty without it.
Field managers `kustomize-controller`/`helm-controller` mean Flux; an
`app.kubernetes.io/instance` label matching an Argo Application (or manager
`argocd-controller`) means Argo CD. If managed, remember safety rule 5:
fixes go to the source repository.

## Cloud provider detection

```bash
aws sts get-caller-identity                          # AWS: account + principal
gcloud config list --format='value(core.project)'    # GCP: active project
az account show --query name -o tsv                  # Azure: subscription
kubectl get nodes -o jsonpath='{.items[0].spec.providerID}'   # provider hint from the cluster itself
```

The `providerID` prefix (`aws:///`, `gce://`, `azure://`) identifies the
platform even when no cloud CLI is authenticated.

## Detecting EKS manually

```bash
kubectl get daemonset aws-node -n kube-system      # VPC CNI — present on virtually every EKS cluster
kubectl get nodes -o jsonpath='{.items[0].spec.providerID}'   # aws:///<az>/<instance-id> on EKS
```

Both signals require only kubectl — no `aws` CLI or credentials needed.
Cluster name and region for the `aws eks`/`aws logs`/`aws elbv2` calls used
by `sre-eks-investigator`: parse the current context
(`kubectl config current-context`), which on `eksctl`/`aws eks
update-kubeconfig`-generated kubeconfigs is either the cluster ARN
(`arn:aws:eks:<region>:<account>:cluster/<name>`) or
`<name>.<region>.eksctl.io` — otherwise ask the user for the cluster name
and region directly.

## Detecting GKE manually

```bash
kubectl get nodes -l cloud.google.com/gke-nodepool   # GKE-specific node label — present in Standard and Autopilot
kubectl get nodes -o jsonpath='{.items[0].spec.providerID}'   # gce://<project>/<zone>/<instance> on GKE
```

Both signals require only kubectl — no `gcloud` CLI or credentials needed.
Cluster name and region/zone for the `gcloud container`/`gcloud logging`/
`gcloud compute` calls used by `sre-gke-investigator`: parse the current
context (`kubectl config current-context`), which on `gcloud container
clusters get-credentials`-generated kubeconfigs is
`gke_<project>_<region-or-zone>_<cluster-name>` — otherwise ask the user
for the project, cluster name, and region/zone directly.

## When there is no cluster access

Work from the repository instead, and open the ledger with the limitation
stated ("no cluster access — findings are static analysis only"):

- Kubernetes manifests, kustomize overlays, Helm values — resource limits,
  probes, image tags, env/config wiring.
- GitOps repo structure — which Kustomization/Application deploys the
  workload, to which cluster and namespace.
- CI/CD config — what a deploy does, when the last one ran.
- Runbooks, docs, previous postmortems in the repo.

Static analysis can rank hypotheses but cannot validate a fix — any
remediation proposed without cluster access must say how the user should
apply and verify it themselves.

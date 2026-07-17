# Command Map

Orientation layer: which `gcloud` group serves which GCP task. Confirm exact flags with `gcloud <group> <command> --help` — surfaces drift between weekly releases. `gcloud help <term>` searches the reference; `gcloud topic` lists concept docs (filters, formats, projections, startup scripts...).

| Task | Group | Everyday commands |
| :--- | :--- | :--- |
| Projects | `gcloud projects` | `list`, `describe`, `create`, `add-iam-policy-binding` |
| IAM | `gcloud iam` | `service-accounts create/list/keys`, `roles describe/create`, `gcloud projects get-iam-policy` |
| VMs | `gcloud compute` | `instances create/list/describe/delete`, `ssh`, `scp`, `disks snapshot`, `addresses`, `firewall-rules`, `images` |
| GKE | `gcloud container` | `clusters create/list/get-credentials` (writes kubeconfig; needs `gke-gcloud-auth-plugin`), `node-pools`, `operations wait` |
| Storage | `gcloud storage` | `ls`, `cp`, `rsync`, `buckets create/describe` (prefer over legacy `gsutil`) |
| Serverless | `gcloud run` / `gcloud functions` / `gcloud app` | `run deploy/services list`, `functions deploy/logs read`, `app deploy/logs tail` |
| Databases | `gcloud sql` / `gcloud firestore` / `gcloud spanner` | `sql instances create`, `sql export sql`, `sql connect` |
| Messaging | `gcloud pubsub` | `topics create/publish`, `subscriptions create/pull` |
| Builds & artifacts | `gcloud builds` / `gcloud artifacts` | `builds submit`, `builds log`, `artifacts repositories create`, `gcloud auth configure-docker REGION-docker.pkg.dev` |
| Secrets & keys | `gcloud secrets` / `gcloud kms` | `secrets create/versions access latest`, `kms encrypt/decrypt` |
| Logging & monitoring | `gcloud logging` | `read 'FILTER' --limit`, `logs list` |
| Networking | `gcloud compute networks` / `gcloud dns` | `networks subnets`, `routers`, `dns record-sets` |
| Org & billing | `gcloud organizations` / `gcloud billing` | `organizations list`, `billing projects link` |
| APIs on/off | `gcloud services` | `enable pubsub.googleapis.com`, `list --available` |
| SDK itself | `gcloud components`, `gcloud config`, `gcloud auth`, `gcloud info` | see the dedicated references |

## Patterns that recur everywhere

- Most groups follow `gcloud <product> <resource> <verb>` with the same verb set (`create`, `list`, `describe`, `update`, `delete`) and honor the global flags: `--project`, `--format`, `--filter`, `--quiet`, `--impersonate-service-account`, `--verbosity`.
- Regional/zonal resources need `--region`/`--zone` unless defaults are set in the configuration (`compute/region`, `compute/zone`, `run/region`).
- Anything missing from GA may exist under `gcloud beta ...`/`gcloud alpha ...` — check `gcloud beta <group> --help` before concluding a capability doesn't exist, but keep alpha/beta out of scripts.
- A first-use error of "API [x.googleapis.com] not enabled" is solved by `gcloud services enable x.googleapis.com` (needs `serviceusage.services.enable` permission), not by re-authenticating.
- IAM permission errors name the missing permission — grant the narrowest matching role with `gcloud projects add-iam-policy-binding PROJECT --member=... --role=...` and mention propagation can take a minute or two.

# Authentication

The single most misunderstood area of the CLI. There are **two separate credential stores**; almost every "authentication doesn't work" report is one being mistaken for the other.

## The two credential worlds

| | CLI credentials | Application Default Credentials (ADC) |
| :--- | :--- | :--- |
| Set by | `gcloud auth login` | `gcloud auth application-default login` |
| Used by | `gcloud`, `bq`, `gsutil` commands | client libraries, Terraform, apps you run locally |
| Inspect | `gcloud auth list` | `~/.config/gcloud/application_default_credentials.json` |
| Revoke | `gcloud auth revoke` | `gcloud auth application-default revoke` |

Symptom → fix: an application/Terraform failing with **"could not find default credentials"** while `gcloud` itself works fine means ADC was never set — run `gcloud auth application-default login` (and `gcloud auth application-default set-quota-project PROJECT_ID` if the library complains about a quota project). Conversely, `gcloud` commands failing while the app works means the CLI credential is missing/expired — `gcloud auth login`.

Both stores live in the user config dir (`~/.config/gcloud` on Linux/macOS, `%APPDATA%\gcloud` on Windows). The CLI resolves credentials in order: access-token env var (`CLOUDSDK_AUTH_ACCESS_TOKEN`) → token file (`--access-token-file`) → credential file → stored login credentials; impersonation, when configured, is applied on top.

## Human sign-in

```bash
gcloud auth login                        # browser flow; account becomes active in the config
gcloud auth login --no-launch-browser    # prints URL + paste code — for SSH/headless with a trusted second device
gcloud auth list                         # who is signed in; * marks active
gcloud config set account NAME@DOMAIN    # switch active account among signed-in ones
```

`gcloud init` bundles auth + project/zone selection and is fine interactively; in automation use the individual commands instead. Workforce identity federation (`gcloud auth login --login-config=...`) covers orgs where humans sign in via external OIDC/SAML IdPs.

## Service accounts — prefer keyless

Ordered by preference:

1. **Attached service account** — on GCE/GKE/Cloud Run/Cloud Build, the runtime's metadata server provides credentials automatically. No setup in the workload; just grant the attached SA the right roles.
2. **Impersonation** — your signed-in identity mints short-lived tokens for a service account. Requires `roles/iam.serviceAccountTokenCreator` on the target SA:

   ```bash
   gcloud compute instances list --impersonate-service-account=deploy@PROJECT.iam.gserviceaccount.com
   gcloud config set auth/impersonate_service_account deploy@PROJECT.iam.gserviceaccount.com   # sticky
   ```

   Also works for ADC: `gcloud auth application-default login --impersonate-service-account=...`.
3. **Workload identity federation** — external workloads (GitHub Actions, other clouds, on-prem) exchange their native OIDC token for GCP credentials via a Workload Identity Pool. No long-lived secret exists at all; `gcloud auth login --cred-file=<generated-config.json>` activates it in the CLI.
4. **Key files — last resort**:

   ```bash
   gcloud auth activate-service-account SA_EMAIL --key-file=key.json
   ```

   A downloaded key is a permanent credential: it needs secure storage, rotation, and is the thing that leaks. Only when nothing above fits (and say so when recommending it).

## Tokens

```bash
gcloud auth print-access-token           # current principal's OAuth token (~1h lifetime)
gcloud auth print-identity-token         # OIDC identity token (e.g., for Cloud Run/IAP)
gcloud auth application-default print-access-token
```

Useful for `curl` against Google APIs or feeding other tools — treat output as a secret: never log it, never commit it.

## CI and headless patterns

- **GitHub Actions**: `google-github-actions/auth` with workload identity federation (keyless), then `setup-gcloud`; the action wires both CLI credentials and ADC.
- **Generic CI with a key secret**: write the key to a file at job start, `gcloud auth activate-service-account --key-file=...`, and prefer also `export GOOGLE_APPLICATION_CREDENTIALS=/path/key.json` so client libraries in the same job get ADC.
- **SSH boxes**: `gcloud auth login --no-launch-browser` (code copy flow) or `--no-browser` (requires a second machine with gcloud).

## Debugging auth quickly

Run the bundled read-only snapshot — it covers accounts, configurations, active properties, `CLOUDSDK_*` overrides, and ADC presence in one shot (path relative to the skill's base directory):

```bash
bash scripts/gcloud-env-report.sh
```

Add `gcloud info --run-diagnostics` for network/property problems. Then match the failing tool to its credential world before touching anything.

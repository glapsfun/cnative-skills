# Install, Components, and Network Setup

## Installing the CLI

Requires Python 3.10–3.14 (installers bundle their own by default). Pick the method by how the machine is managed — it determines how updates work later:

| Method | Install | Updates |
| :--- | :--- | :--- |
| Interactive installer (Linux/macOS archive + `install.sh`, Windows `GoogleCloudSDKInstaller.exe`) | Extracts to `google-cloud-sdk/`, offers PATH + completion setup | `gcloud components update` |
| Homebrew (macOS) | `brew install gcloud-cli` | `brew upgrade` (component commands may be limited) |
| apt (Debian/Ubuntu) | add `packages.cloud.google.com` repo, `apt-get install google-cloud-cli` | `apt-get update && apt-get upgrade`; pin/downgrade with `apt-get install google-cloud-cli=VERSION-0` |
| dnf/yum (RHEL/Fedora) | repo + `dnf install google-cloud-cli` | `dnf upgrade` |
| snap | `snap install google-cloud-cli --classic` | automatic |
| Docker | `gcr.io/google.com/cloudsdktool/google-cloud-cli` image (`:stable`, `:slim`, versioned tags) | pull a newer tag |

After any install, initialize with `gcloud init` (or non-interactively: `gcloud auth login` / `activate-service-account` + `gcloud config set` — see `auth.md` and `config-properties.md`).

## Components

The SDK is modular. Defaults include `gcloud` (GA), `bq`, `gsutil`, `core`; everything else is opt-in:

```bash
gcloud components list                  # installed + available, with versions
gcloud components install kubectl gke-gcloud-auth-plugin
gcloud components update                # whole SDK to latest
gcloud components update --version 576.0.0   # pin/downgrade the whole SDK
gcloud components remove <id>
```

Notable components: `kubectl`, `gke-gcloud-auth-plugin` (required for GKE kubeconfig auth), `alpha`, `beta`, `pubsub-emulator`, `cloud-run-proxy`, `terraform-tools`, `package-go-module`. Running a `gcloud alpha/beta ...` command interactively prompts to install the track; `alpha` = experimental, `beta` = pre-GA — both can change or disappear, so scripts should stick to GA surfaces.

**The classic gotcha:** package-manager installs (apt/dnf/snap) **disable** `gcloud components` — you'll get "The component manager is disabled for this installation". Install extras as OS packages instead: `apt-get install google-cloud-cli-gke-gcloud-auth-plugin`, `google-cloud-cli-kubectl`... (same names on dnf). Diagnose which world you're in with `gcloud info --format="value(installation.sdk_root)"` — `/usr/lib/google-cloud-sdk` means package-managed.

Note `gsutil` is legacy for most uses — prefer `gcloud storage` commands (faster, consistent flags) unless the user needs gsutil-specific features.

## Proxy settings

For gcloud behind a corporate proxy:

```bash
gcloud config set proxy/type http        # http | http_no_tunnel | socks4 | socks5
gcloud config set proxy/address proxy.corp.example
gcloud config set proxy/port 8080
# credentials — prefer env vars so they stay out of config files:
export CLOUDSDK_PROXY_USERNAME=user
export CLOUDSDK_PROXY_PASSWORD=secret
```

Standard `http_proxy`/`https_proxy`/`no_proxy` env vars are honored too; gcloud-specific properties win when both are set.

**TLS-intercepting proxies** (SSL handshake / certificate verify failures): point gcloud at the corporate CA bundle:

```bash
gcloud config set core/custom_ca_certs_file /path/to/corp-ca.pem
```

## Diagnostics

`gcloud info` dumps installation, config, and environment details; `gcloud info --run-diagnostics` actively tests network reachability and hidden property conflicts — the fastest first move on "gcloud can't connect" reports.

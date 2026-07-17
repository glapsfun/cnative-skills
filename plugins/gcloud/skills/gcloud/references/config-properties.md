# Configurations and Properties

## Properties

Properties are `section/name` key-values controlling CLI behavior:

```bash
gcloud config list                       # active configuration's properties
gcloud config set core/project my-proj   # "core/" may be omitted: gcloud config set project
gcloud config get-value project
gcloud config unset compute/zone
```

Common ones: `core/project`, `core/account`, `compute/region`, `compute/zone`, `container/cluster`, `run/region`, `core/disable_prompts`, `core/verbosity`, `auth/impersonate_service_account`, `proxy/*`, `core/custom_ca_certs_file`.

**Precedence (highest wins):**

1. Command-line flags — `--project`, `--zone`, `--account`, ...
2. Environment variables — `CLOUDSDK_SECTION_PROPERTY` (e.g., `CLOUDSDK_CORE_PROJECT=my-proj`, `CLOUDSDK_COMPUTE_ZONE=europe-west1-b`)
3. Active configuration's stored properties

This matters when debugging "gcloud is using the wrong project": check for an env var override before blaming the config (`env | grep CLOUDSDK`, and `gcloud info` shows effective values with their origin).

## Named configurations

A configuration is a named property set; exactly one is active. The `default` configuration exists after install. Use one configuration per project/account/environment combination:

```bash
gcloud config configurations create work
gcloud config set project work-proj          # writes into the now-active "work"
gcloud config set account me@company.com
gcloud config configurations create personal
gcloud config configurations list           # NAME  IS_ACTIVE  ACCOUNT  PROJECT ...
gcloud config configurations activate work
gcloud config configurations describe personal
gcloud config configurations delete old     # cannot delete the active one
```

Configurations are stored under `~/.config/gcloud/configurations/config_<name>`.

## Switching without switching

Two override mechanisms avoid flip-flopping the global active configuration:

```bash
gcloud compute instances list --configuration=personal   # one command
export CLOUDSDK_ACTIVE_CONFIG_NAME=work                  # this shell/session only
```

The env var is the right tool for parallel terminals on different projects, CI jobs, and per-directory automation (direnv: put the export in `.envrc`). Signed-in accounts (`gcloud auth login`) are shared across configurations — a configuration selects which account/project is active, it doesn't hold its own credentials.

For one-off cross-project commands, plain `--project=other-proj` is lighter than a configuration switch.

## Multi-project workflow example

```bash
# once:
gcloud config configurations create prod
gcloud config set project acme-prod && gcloud config set account sre@acme.com
gcloud config configurations create dev
gcloud config set project acme-dev && gcloud config set account me@acme.com

# daily:
gcloud config configurations activate dev
CLOUDSDK_ACTIVE_CONFIG_NAME=prod gcloud compute instances list   # peek at prod without switching
```

Keep destructive work deliberate: before any mutation, confirm the target with `gcloud config get-value project` (or force it explicitly with `--project`) — running a delete against the wrong active configuration is the classic multi-project accident.

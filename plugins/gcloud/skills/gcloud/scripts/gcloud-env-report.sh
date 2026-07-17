#!/usr/bin/env bash
set -euo pipefail

# Read-only snapshot of the local gcloud environment: named configurations,
# signed-in accounts, active properties, and whether Application Default
# Credentials exist — the facts needed to debug auth/config issues.
#
# Security posture:
# - Read-only: only `gcloud ... list/--format` inspection commands and local
#   file existence checks; nothing is modified and no network calls are made
#   by this script itself (gcloud inspection commands read local state).
# - Prints no secrets: tokens and key material are never read; for ADC only
#   the credential *type* field is extracted, never the credential values.

usage() {
  cat <<'EOF'
Usage: gcloud-env-report.sh [-h|--help]

Print a read-only report of gcloud state: configurations, accounts, active
properties, and ADC presence. No secrets are printed and nothing is changed.
EOF
}

if [ "$#" -gt 1 ]; then
  echo "unexpected extra arguments" >&2
  usage >&2
  exit 2
fi

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    echo "unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found (install: https://docs.cloud.google.com/sdk/docs/install-sdk)" >&2
  exit 1
fi

failures=0

echo "Named configurations:"
gcloud config configurations list \
  --format="table(name, is_active, properties.core.account, properties.core.project)" 2>/dev/null \
  | sed 's/^/  /' || {
  echo "  (could not list configurations)"
  failures=$((failures + 1))
}

echo
echo "Signed-in accounts (gcloud auth list):"
gcloud auth list --format="table(account, status)" 2>/dev/null \
  | sed 's/^/  /' || {
  echo "  (could not list accounts)"
  failures=$((failures + 1))
}

echo
echo "Active properties:"
# One gcloud call for all five properties (each spawn costs ~0.5-1s); value()
# keeps unset fields as empty tab-separated slots.
if props_line="$(gcloud config list \
  --format='value(core.account, core.project, compute.region, compute.zone, auth.impersonate_service_account)' 2>/dev/null)"; then
  IFS=$'\t' read -r p_account p_project p_region p_zone p_impersonate <<<"${props_line}" || true
  echo "  core/account: ${p_account:-<unset>}"
  echo "  core/project: ${p_project:-<unset>}"
  echo "  compute/region: ${p_region:-<unset>}"
  echo "  compute/zone: ${p_zone:-<unset>}"
  echo "  auth/impersonate_service_account: ${p_impersonate:-<unset>}"
else
  echo "  (could not read properties)"
  failures=$((failures + 1))
fi

if [ -n "${CLOUDSDK_ACTIVE_CONFIG_NAME:-}" ]; then
  echo
  echo "Note: CLOUDSDK_ACTIVE_CONFIG_NAME=${CLOUDSDK_ACTIVE_CONFIG_NAME} overrides the active configuration in this shell."
fi
overrides="$(env | grep -E '^CLOUDSDK_[A-Z_]+=' | grep -v '^CLOUDSDK_ACTIVE_CONFIG_NAME=' | cut -d= -f1 || true)"
if [ -n "${overrides}" ]; then
  echo
  echo "Property overrides via environment (these beat 'gcloud config set'):"
  printf '%s\n' "${overrides}" | sed 's/^/  /'
fi

echo
config_dir="${CLOUDSDK_CONFIG:-${HOME}/.config/gcloud}"
adc_file="${GOOGLE_APPLICATION_CREDENTIALS:-${config_dir}/application_default_credentials.json}"
if [ -f "${adc_file}" ]; then
  adc_type="unknown"
  if command -v python3 >/dev/null 2>&1; then
    # Extract only the credential type; never print credential contents.
    adc_type="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("type", "unknown"))' "${adc_file}" 2>/dev/null || echo unknown)"
    if ! [[ ${adc_type} =~ ^[a-z_]{1,40}$ ]]; then
      adc_type="unknown"
    fi
  fi
  echo "Application Default Credentials: present (${adc_file}, type: ${adc_type})"
else
  echo "Application Default Credentials: not set (${adc_file} missing)"
  echo "  Apps/client libraries will fail with 'could not find default credentials' — see references/auth.md"
fi
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  echo "  Note: GOOGLE_APPLICATION_CREDENTIALS is set and overrides the default ADC location."
fi

if [ "${failures}" -gt 0 ]; then
  echo "warning: ${failures} section(s) could not be read; the report above is incomplete" >&2
  exit 1
fi

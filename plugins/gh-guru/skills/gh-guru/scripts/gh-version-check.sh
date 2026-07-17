#!/usr/bin/env bash
set -euo pipefail

# Reports the latest upstream gh CLI release next to the skill's baseline,
# the locally installed gh version and auth status, the current repository
# context, and whether actionlint is available for workflow validation.
#
# Security posture:
# - Read-only: one HTTPS GET to api.github.com plus read-only local checks
#   (`gh --version`, `gh auth status`, `git remote`); nothing fetched is
#   executed.
# - Every value taken from the API response (tag, date, URL) is validated
#   against a strict character allowlist before printing, so release metadata
#   cannot inject free-form text into the agent's context.
#
# Failure behavior: if curl or python3 is missing, or the API call fails
# (offline, rate limit), the upstream fields degrade to "unknown" with a
# warning on stderr and the local report still prints.

REPO_DEFAULT="cli/cli"
BASELINE_DEFAULT="v2.96.0"

usage() {
  cat <<EOF
Usage: gh-version-check.sh [-h|--help]

Report the installed gh CLI version, auth status, repository context, and
the latest upstream cli/cli release versus the skill baseline. Read-only.

Environment:
  GH_GURU_REPO       Upstream repo to check (default: ${REPO_DEFAULT})
  GH_GURU_BASELINE   Skill baseline version (default: ${BASELINE_DEFAULT})
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

REPO="${GH_GURU_REPO:-${REPO_DEFAULT}}"
BASELINE="${GH_GURU_BASELINE:-${BASELINE_DEFAULT}}"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
CURL_ARGS=(-fsSL --proto '=https' --connect-timeout 5 --max-time 15)

latest_json=""
if ! command -v curl >/dev/null 2>&1; then
  echo "warning: curl not found; skipping the upstream release check" >&2
elif ! command -v python3 >/dev/null 2>&1; then
  echo "warning: python3 not found; skipping the upstream release check" >&2
elif ! latest_json="$(curl "${CURL_ARGS[@]}" "${API_URL}")"; then
  echo "warning: could not fetch ${API_URL} (network error or API rate limit); reporting local information only" >&2
  latest_json=""
fi

latest_tag=""
published_at=""
release_url=""
if [ -n "${latest_json}" ]; then
  # One parse for all three fields; values are sanitized below either way.
  release_fields="$(printf '%s' "${latest_json}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for key in ("tag_name", "published_at", "html_url"):
    print(d.get(key, ""))' 2>/dev/null)" || release_fields=""
  {
    read -r latest_tag
    read -r published_at
    read -r release_url
  } <<<"${release_fields}" || true
fi

# Sanitize API-derived values: allowlisted characters only, no free-form text.
if ! [[ ${latest_tag} =~ ^[0-9A-Za-z._-]{1,64}$ ]]; then
  latest_tag=""
fi
if ! [[ ${published_at} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  published_at=""
fi
# Literal prefix comparison (no regex interpolation of ${REPO}); the remaining
# tag segment must match the same allowlist as latest_tag.
release_prefix="https://github.com/${REPO}/releases/tag/"
release_tag_part="${release_url#"${release_prefix}"}"
if [ "${release_tag_part}" = "${release_url}" ] \
  || ! [[ ${release_tag_part} =~ ^[0-9A-Za-z._-]{1,64}$ ]]; then
  release_url=""
fi

echo "gh upstream latest: ${latest_tag:-unknown}"
echo "Published: ${published_at:-unknown}"
echo "Release notes: ${release_url:-${API_URL}}"
echo "Skill baseline snapshot: ${BASELINE}"

if [ -n "${latest_tag}" ] && [ "${latest_tag}" != "${BASELINE}" ]; then
  echo "Notice: upstream latest differs from the skill baseline; inspect release notes before version-specific advice."
fi

echo
if command -v gh >/dev/null 2>&1; then
  echo "Local gh CLI:"
  gh --version || true
  echo
  echo "Auth status:"
  # `gh auth status` exits non-zero when not logged in; report either way.
  gh auth status 2>&1 | sed 's/^/  /' || true
else
  echo "Local gh CLI: not found (install: https://cli.github.com)"
fi

echo
if command -v actionlint >/dev/null 2>&1; then
  echo "actionlint: $(actionlint --version 2>/dev/null | head -n 1)"
else
  echo "actionlint: not found (optional; validates workflow YAML)"
fi

if command -v git >/dev/null 2>&1 \
  && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo
  echo "Repository context:"
  echo "  branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  git remote -v 2>/dev/null | sed 's/^/  remote: /' || true
  workflow_dir="$(git rev-parse --show-toplevel 2>/dev/null)/.github/workflows"
  if [ -d "${workflow_dir}" ]; then
    echo "  workflows: $(find "${workflow_dir}" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) | wc -l | tr -d ' ') file(s) in .github/workflows"
  else
    echo "  workflows: no .github/workflows directory"
  fi
fi

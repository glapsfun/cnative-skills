#!/usr/bin/env bash
set -euo pipefail

# Reports the latest upstream glab CLI release next to the skill's baseline,
# the locally installed glab version and auth status, the current repository
# context, and whether a .gitlab-ci.yml exists for pipeline work.
#
# Security posture:
# - Read-only: one HTTPS GET to gitlab.com plus read-only local checks
#   (`glab version`, `glab auth status`, `git remote`); nothing fetched is
#   executed.
# - Every value taken from the API response (tag, date) is validated against
#   a strict character allowlist before printing, so release metadata cannot
#   inject free-form text into the agent's context.
#
# Failure behavior: if curl or python3 is missing, or the API call fails
# (offline, rate limit), the upstream fields degrade to "unknown" with a
# warning on stderr and the local report still prints.

PROJECT_DEFAULT="gitlab-org%2Fcli"
BASELINE_DEFAULT="v1.108.0"

usage() {
  cat <<EOF
Usage: glab-version-check.sh [-h|--help]

Report the installed glab CLI version, auth status, repository context, and
the latest upstream gitlab-org/cli release versus the skill baseline.
Read-only.

Environment:
  GLAB_GURU_PROJECT    URL-encoded upstream project path (default: ${PROJECT_DEFAULT})
  GLAB_GURU_BASELINE   Skill baseline version (default: ${BASELINE_DEFAULT})
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

PROJECT="${GLAB_GURU_PROJECT:-${PROJECT_DEFAULT}}"
BASELINE="${GLAB_GURU_BASELINE:-${BASELINE_DEFAULT}}"
API_URL="https://gitlab.com/api/v4/projects/${PROJECT}/releases/permalink/latest"
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
released_at=""
if [ -n "${latest_json}" ]; then
  # One parse for both fields; values are sanitized below either way.
  release_fields="$(printf '%s' "${latest_json}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for key in ("tag_name", "released_at"):
    print(d.get(key, ""))' 2>/dev/null)" || release_fields=""
  {
    read -r latest_tag
    read -r released_at
  } <<<"${release_fields}" || true
fi

# Sanitize API-derived values: allowlisted characters only, no free-form text.
if ! [[ ${latest_tag} =~ ^[0-9A-Za-z._-]{1,64}$ ]]; then
  latest_tag=""
fi
if ! [[ ${released_at} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$ ]]; then
  released_at=""
fi

release_url=""
if [ -n "${latest_tag}" ]; then
  release_url="https://gitlab.com/gitlab-org/cli/-/releases/${latest_tag}"
fi

echo "glab upstream latest: ${latest_tag:-unknown}"
echo "Released: ${released_at:-unknown}"
echo "Release notes: ${release_url:-${API_URL}}"
echo "Skill baseline snapshot: ${BASELINE}"

if [ -n "${latest_tag}" ] && [ "${latest_tag}" != "${BASELINE}" ]; then
  echo "Notice: upstream latest differs from the skill baseline; inspect release notes before version-specific advice."
fi

echo
if command -v glab >/dev/null 2>&1; then
  echo "Local glab CLI:"
  glab version 2>/dev/null | sed 's/^/  /' || true
  echo
  echo "Auth status:"
  # `glab auth status` exits non-zero when not logged in; report either way.
  glab auth status 2>&1 | sed 's/^/  /' || true
else
  echo "Local glab CLI: not found (install: https://gitlab.com/gitlab-org/cli/-/releases or 'brew install glab')"
fi

if command -v git >/dev/null 2>&1 \
  && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo
  echo "Repository context:"
  echo "  branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  git remote -v 2>/dev/null | sed 's/^/  remote: /' || true
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -f "${toplevel}/.gitlab-ci.yml" ]; then
    echo "  ci config: .gitlab-ci.yml present (validate with: glab ci lint --dry-run --include-jobs)"
  else
    ci_files=0
    if [ -d "${toplevel}/.gitlab" ]; then
      # `|| true` guards pipefail: an unreadable subdirectory makes find exit
      # non-zero, which must degrade the count, not abort the report.
      ci_files="$(find "${toplevel}/.gitlab" -maxdepth 2 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | wc -l | tr -d ' ' || true)"
      ci_files="${ci_files:-0}"
    fi
    if [ "${ci_files}" -gt 0 ]; then
      echo "  ci config: no root .gitlab-ci.yml, but ${ci_files} YAML file(s) under .gitlab/ (custom CI config path?)"
    else
      echo "  ci config: no .gitlab-ci.yml found"
    fi
  fi
fi

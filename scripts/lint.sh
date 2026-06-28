#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/lint.sh

Lint shell (shellcheck), YAML (yamllint), Markdown (markdownlint-cli2),
and GitHub Actions workflows (actionlint). Operates on git-tracked files.
  -h, --help  Show this help.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

cd "$REPO_ROOT"
status=0

if skip_unless_tool shellcheck; then
  mapfile -t sh_files < <(git ls-files '*.sh')
  if [[ ${#sh_files[@]} -gt 0 ]]; then
    shellcheck -- "${sh_files[@]}" || status=1
  fi
fi

if skip_unless_tool yamllint; then
  mapfile -t yaml_files < <(git ls-files '*.yml' '*.yaml')
  if [[ ${#yaml_files[@]} -gt 0 ]]; then
    yamllint -c .yamllint -- "${yaml_files[@]}" || status=1
  fi
fi

if skip_unless_tool markdownlint-cli2; then
  # Lint only git-tracked Markdown (markdownlint-cli2 otherwise globs the whole
  # filesystem, including untracked/ignored dirs that do not exist in CI).
  mapfile -t md_files < <(git ls-files '*.md')
  if [[ ${#md_files[@]} -gt 0 ]]; then
    markdownlint-cli2 "${md_files[@]}" || status=1
  fi
fi

if skip_unless_tool actionlint; then
  actionlint || status=1
fi

if ((status != 0)); then
  log_error "lint problems found"
  exit 1
fi
log_ok "lint passed"

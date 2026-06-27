#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SHFMT_FLAGS=(-i 2 -ci -bn)

usage() {
  cat <<'EOF'
Usage: scripts/fmt.sh [--check]

Format shell scripts (shfmt) and JSON/YAML (prettier).
  --check     Report unformatted files and exit non-zero; do not write.
  -h, --help  Show this help.
EOF
}

check=false
case "${1:-}" in
  --check) check=true ;;
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

if skip_unless_tool shfmt; then
  mapfile -t sh_files < <(git ls-files '*.sh')
  if [[ ${#sh_files[@]} -gt 0 ]]; then
    if "$check"; then
      shfmt "${SHFMT_FLAGS[@]}" -d -- "${sh_files[@]}" || status=1
    else
      shfmt "${SHFMT_FLAGS[@]}" -w -- "${sh_files[@]}"
    fi
  fi
fi

if skip_unless_tool prettier; then
  mapfile -t fmt_files < <(git ls-files '*.json' '*.yml' '*.yaml')
  if [[ ${#fmt_files[@]} -gt 0 ]]; then
    if "$check"; then
      prettier --check --ignore-path .prettierignore -- "${fmt_files[@]}" || status=1
    else
      prettier --write --ignore-path .prettierignore -- "${fmt_files[@]}"
    fi
  fi
fi

if ((status != 0)); then
  log_error "formatting issues found; run scripts/fmt.sh to fix"
  exit 1
fi
log_ok "formatting ok"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/check.sh [--all]

Run the developer check suite.
  (default)   Fast suite: fmt --check, lint, validate --fast.
  --all       Everything CI runs: also validate --slow, test, install-test, security.
  -h, --help  Show this help.
EOF
}

all=false
case "${1:-}" in
  --all) all=true ;;
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

run() {
  log_info "==> $*"
  "$@"
}

run "$SCRIPT_DIR/fmt.sh" --check
run "$SCRIPT_DIR/lint.sh"
run "$SCRIPT_DIR/validate.sh" --fast

if "$all"; then
  run "$SCRIPT_DIR/validate.sh" --slow
  run "$SCRIPT_DIR/test.sh"
  run "$SCRIPT_DIR/install-test.sh"
  run "$SCRIPT_DIR/security.sh"
fi

log_ok "all checks passed"

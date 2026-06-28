#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/security.sh [--staged]

Scan for secrets with gitleaks.
  --staged    Scan staged changes only (fast; for pre-commit).
  (default)   Scan the full git history.
  -h, --help  Show this help.
EOF
}

staged=false
case "${1:-}" in
  --staged) staged=true ;;
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
skip_unless_tool gitleaks || exit 0

if "$staged"; then
  gitleaks protect --staged --redact --no-banner
else
  gitleaks detect --redact --no-banner
fi
log_ok "no secrets detected"

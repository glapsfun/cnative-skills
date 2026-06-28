#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/release-dryrun.sh vX.Y.Z[-rc.N]

Preflight a release without publishing:
  - refuse on a dirty working tree
  - validate the tag is semver and does not already exist
  - run scripts/check.sh --all (the release gate)
  - preview the changelog git-cliff would generate
  -h, --help  Show this help.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "")
    log_error "a version tag is required, e.g. v1.2.0"
    usage
    exit 2
    ;;
esac

tag="$1"
cd "$REPO_ROOT"

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
  log_error "tag '$tag' is not vX.Y.Z or vX.Y.Z-rc.N"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  log_error "working tree is dirty; commit or stash before releasing"
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  log_error "tag '$tag' already exists"
  exit 1
fi

log_info "running release gate: scripts/check.sh --all"
"$SCRIPT_DIR/check.sh" --all

if [[ "$tag" == *-rc.* ]]; then
  log_info "classification: PRERELEASE"
else
  log_info "classification: stable release"
fi

if skip_unless_tool git-cliff; then
  log_info "changelog preview for $tag:"
  git-cliff --unreleased --tag "$tag"
fi

log_ok "dry-run complete; '$tag' is ready to tag and push"

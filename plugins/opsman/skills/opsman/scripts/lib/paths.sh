# shellcheck shell=sh
# shellcheck disable=SC2034  # path variables are consumed by sourcing scripts
# Control-plane paths in the target repository. OPSMAN_ROOT is overridable.

opsman_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

OPSMAN_ROOT=${OPSMAN_ROOT:-$(opsman_repo_root)}
OPSMAN_DIR=$OPSMAN_ROOT/.opsman
OPSMAN_RUNS_DIR=$OPSMAN_DIR/runs
OPSMAN_REGISTRY_DIR=$OPSMAN_DIR/registry
OPSMAN_LOCK_DIR=$OPSMAN_DIR/lock
OPSMAN_CURRENT_FILE=$OPSMAN_DIR/current

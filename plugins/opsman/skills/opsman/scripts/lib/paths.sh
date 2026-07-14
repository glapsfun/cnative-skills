# shellcheck shell=sh
# shellcheck disable=SC2034  # path variables are consumed by sourcing scripts
# Control-plane paths in the target repository. OPSMAN_ROOT is overridable.

# Refuse to run outside a git repository rather than littering $PWD with
# an .opsman/ control plane; an explicit OPSMAN_ROOT overrides.
if [ -z "${OPSMAN_ROOT:-}" ]; then
  if ! OPSMAN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    printf 'opsman: not inside a git repository (set OPSMAN_ROOT to override)\n' >&2
    exit 2
  fi
fi
OPSMAN_DIR=$OPSMAN_ROOT/.opsman
OPSMAN_RUNS_DIR=$OPSMAN_DIR/runs
OPSMAN_REGISTRY_DIR=$OPSMAN_DIR/registry
OPSMAN_WORKTREES_DIR=$OPSMAN_DIR/worktrees
OPSMAN_STEP_WORKTREES_DIR=$OPSMAN_DIR/step-worktrees
OPSMAN_LOCK_DIR=$OPSMAN_DIR/lock
OPSMAN_CURRENT_FILE=$OPSMAN_DIR/current

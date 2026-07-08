#!/bin/sh
# Cooperative control-plane lock: mkdir is atomic on POSIX filesystems.
# Never breaks a held lock; reports staleness for a human to resolve.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"

mkdir -p "$OPSMAN_DIR"
if mkdir "$OPSMAN_LOCK_DIR" 2>/dev/null; then
  printf '%s\n' "${PPID:-$$}" >"$OPSMAN_LOCK_DIR/pid"
  exit 0
fi

holder=$(cat "$OPSMAN_LOCK_DIR/pid" 2>/dev/null || printf 'unknown')
if [ "$holder" != "unknown" ] && ! kill -0 "$holder" 2>/dev/null; then
  die "$EX_LOCK" "stale lock at $OPSMAN_LOCK_DIR (pid $holder is not running) — release with release-lock.sh"
fi
die "$EX_LOCK" "lock held by pid $holder at $OPSMAN_LOCK_DIR"

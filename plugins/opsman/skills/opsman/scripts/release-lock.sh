#!/bin/sh
# Releases the control-plane lock. Idempotent.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"

rm -f "$OPSMAN_LOCK_DIR/pid"
rmdir "$OPSMAN_LOCK_DIR" 2>/dev/null || true

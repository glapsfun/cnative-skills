#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo"

"$SCRIPTS_DIR/acquire-lock.sh"
[ -d "$repo/.opsman/lock" ] || fail "lock dir not created"
assert_file "$repo/.opsman/lock/pid"

# second acquisition fails with exit 4
assert_status 4 "$SCRIPTS_DIR/acquire-lock.sh"

# release is idempotent
"$SCRIPTS_DIR/release-lock.sh"
[ ! -d "$repo/.opsman/lock" ] || fail "lock dir survived release"
"$SCRIPTS_DIR/release-lock.sh"

# reacquire after release works
"$SCRIPTS_DIR/acquire-lock.sh"
"$SCRIPTS_DIR/release-lock.sh"

# stale lock (dead pid) is still refused but reported as stale
mkdir -p "$repo/.opsman/lock"
printf '999999\n' >"$repo/.opsman/lock/pid"
set +e
err=$("$SCRIPTS_DIR/acquire-lock.sh" 2>&1)
code=$?
set -e
assert_eq "$code" 4 "stale lock exit"
case $err in
  *stale*) : ;;
  *) fail "expected staleness hint, got: $err" ;;
esac
"$SCRIPTS_DIR/release-lock.sh"

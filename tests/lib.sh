#!/usr/bin/env bash
# Shared helpers for tests/*.test.sh. Sourced after the test has cd'd to the
# repo root; callers set $s to the script under test before using expect_exit2.

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# expect_exit2 <desc> [args...] — run "$s" with args and require exit 2.
# The failure is captured via `|| rc=$?`, so errexit does not fire.
expect_exit2() {
  local desc="$1" rc=0
  shift
  # shellcheck disable=SC2154  # $s is the script under test, set by the sourcing test file
  "$s" "$@" >/dev/null 2>&1 || rc=$?
  [[ $rc -eq 2 ]] || fail "$desc should exit 2 (got $rc)"
}

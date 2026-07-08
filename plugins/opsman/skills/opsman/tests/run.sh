#!/bin/sh
# Runs every t-*.sh in this directory; prints ok/FAIL per test.
set -u

dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
rc=0
for t in "$dir"/t-*.sh; do
  [ -e "$t" ] || continue
  if out=$(sh "$t" 2>&1); then
    printf 'ok   %s\n' "$(basename "$t")"
  else
    printf 'FAIL %s\n%s\n' "$(basename "$t")" "$out"
    rc=1
  fi
done
exit "$rc"

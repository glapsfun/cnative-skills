#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# Parallel plan-step execution: ready-steps, step-run, step-land.
. "$(dirname -- "$0")/lib.sh"

# --- unit: lib/scope.sh snapshot_delta --------------------------------------
. "$SCRIPTS_DIR/lib/common.sh"
. "$SCRIPTS_DIR/lib/scope.sh"

pre=$sandbox/pre.tsv
post=$sandbox/post.tsv

# unchanged path: no delta
printf 'aaa\tsame.txt\n' >"$pre"
printf 'aaa\tsame.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "" "unchanged path produces no delta"

# modified path: reported
printf 'aaa\tchanged.txt\n' >"$pre"
printf 'bbb\tchanged.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "$(printf 'bbb\tchanged.txt')" "modified path is delta"

# new path (absent from pre): reported
: >"$pre"
printf 'ccc\tnew.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "$(printf 'ccc\tnew.txt')" "new path is delta"

# mix of changed, new, and unchanged
printf 'aaa\tsame.txt\nbbb\told.txt\n' >"$pre"
printf 'aaa\tsame.txt\nzzz\told.txt\nccc\tnew.txt\n' >"$post"
want=$(printf 'zzz\told.txt\nccc\tnew.txt')
assert_eq "$(snapshot_delta "$pre" "$post")" "$want" "mixed snapshot reports only changed/new paths"

printf 'ok\n'

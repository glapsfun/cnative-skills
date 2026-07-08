#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
K=$SCRIPTS_DIR/opsman

run_to_implementing

# judge is state-guarded: IMPLEMENTING is not JUDGING
assert_status 3 "$K" judge

run_to_judging
"$K" judge | grep -q 'Role: Oracle' || fail "judge did not render the oracle packet"

# invalid artifacts refuse judging
mv "$rd/problem.yaml" "$rd/problem.yaml.bak"
assert_status 5 "$K" judge
mv "$rd/problem.yaml.bak" "$rd/problem.yaml"
"$K" judge >/dev/null || fail "judge did not recover after artifact restore"

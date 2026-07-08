#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
R=$SCRIPTS_DIR/record-event.sh

# defaults written at init
mkskill ".claude/skills/probe" probe "probe fixture skill"
"$SCRIPTS_DIR/build-registry.sh"
run_id=$("$SCRIPTS_DIR/init-run.sh" "budget defaults" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
assert_file "$rd/limits.json"
assert_eq "$(jq -r '.max_iterations' "$rd/limits.json")" 5
assert_eq "$(jq -r '.max_runtime_commands' "$rd/limits.json")" 100
"$R" --run "$run_id" --event RunAbandoned

# unknown keys and malformed values are usage errors (checked before the lock)
assert_status 2 "$SCRIPTS_DIR/init-run.sh" --limit nope=3 "bad key"
assert_status 2 "$SCRIPTS_DIR/init-run.sh" --limit max_iterations=abc "bad value"

# overrides apply
run_id=$("$SCRIPTS_DIR/init-run.sh" --limit max_iterations=2 --limit max_changed_files=1 "budget overrides" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
assert_eq "$(jq -r '.max_iterations' "$rd/limits.json")" 2
assert_eq "$(jq -r '.max_changed_files' "$rd/limits.json")" 1
assert_eq "$(jq -r '.max_failed_attempts_per_hypothesis' "$rd/limits.json")" 2
"$R" --run "$run_id" --event RunAbandoned

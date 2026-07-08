#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
K=$SCRIPTS_DIR/opsman

# no verb / unknown verb / future verb: exit 2
assert_status 2 "$K"
assert_status 2 "$K" frobnicate
assert_status 2 "$K" next
assert_status 2 "$K" judge

# status before any run: exit 2 with guidance
assert_status 2 "$K" status

# start: builds registry and initializes a run
mkdir -p "$repo/.claude/skills/foo"
printf -- '---\nname: foo\ndescription: foo skill\n---\n' >"$repo/.claude/skills/foo/SKILL.md"
run_id=$("$K" start "fix the widget" | tail -n 1)
assert_file "$repo/.opsman/registry/skills.json"
assert_file "$repo/.opsman/runs/$run_id/state.json"
assert_eq "$(command cat "$repo/.opsman/current")" "$run_id"

# status prints the STATE.md of the current run
"$K" status | grep -q DISCOVERING || fail "status missing state"

# record routes to the current run
"$K" record --event SkillsIndexed
"$K" status | grep -q UNDERSTANDING || fail "record did not advance state"

# validate-run on current run passes
"$K" validate-run

# map rebuilds the registry
rm -rf "$repo/.opsman/registry"
"$K" map
assert_file "$repo/.opsman/registry/skills.json"

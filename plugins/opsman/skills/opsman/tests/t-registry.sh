#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

mkdir -p "$repo/.claude/skills/foo/agents" "$repo/.claude/skills/foo/scripts"
printf -- '---\nname: foo\ndescription: foo skill\n---\n' >"$repo/.claude/skills/foo/SKILL.md"
printf 'x\n' >"$repo/.claude/skills/foo/agents/helper.md"
printf '#!/bin/sh\n' >"$repo/.claude/skills/foo/scripts/tool.sh"
# duplicate foo in a lower-precedence root: must lose
mkdir -p "$repo/plugins/foo/skills/foo"
printf -- '---\nname: foo\ndescription: loser duplicate\n---\n' >"$repo/plugins/foo/skills/foo/SKILL.md"
mkdir -p "$repo/plugins/bar/skills/bar"
printf -- '---\nname: bar\ndescription: bar skill\n---\n' >"$repo/plugins/bar/skills/bar/SKILL.md"

"$SCRIPTS_DIR/build-registry.sh"
reg=$repo/.opsman/registry
for f in skills.json agents.json scripts.json capability-map.md registry.sha256; do
  assert_file "$reg/$f"
done

# dedup kept the higher-precedence foo; base team (4) always present;
# sorted by name; no precedence key on any entry
assert_eq "$(jq -r 'length' "$reg/skills.json")" 6
assert_eq "$(jq -r '.[0].name' "$reg/skills.json")" bar
assert_eq "$(jq -r '.[] | select(.name == "foo") | .description' "$reg/skills.json")" "foo skill"
assert_eq "$(jq -r '[.[] | select(has("precedence"))] | length' "$reg/skills.json")" 0

# agents/scripts indexed
assert_eq "$(jq -r '.[0].skill' "$reg/agents.json")" foo
jq -e '.[0].path | endswith("agents/helper.md")' "$reg/agents.json" >/dev/null || fail "agent path"
jq -e '.[0].path | endswith("scripts/tool.sh")' "$reg/scripts.json" >/dev/null || fail "script path"

# capability map mentions both skills
grep -q 'foo skill' "$reg/capability-map.md" || fail "capability map missing foo"
grep -q 'bar skill' "$reg/capability-map.md" || fail "capability map missing bar"

# determinism: rebuild and byte-compare every artifact
mkdir -p "$sandbox/snap"
cp "$reg"/* "$sandbox/snap/"
"$SCRIPTS_DIR/build-registry.sh"
for f in skills.json agents.json scripts.json capability-map.md registry.sha256; do
  cmp -s "$reg/$f" "$sandbox/snap/$f" || fail "not deterministic: $f"
done

# --output writes elsewhere
"$SCRIPTS_DIR/build-registry.sh" --output "$sandbox/alt"
assert_file "$sandbox/alt/skills.json"

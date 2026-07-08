#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

mkskill "$repo/.claude/skills/foo" foo "repo-local foo skill"
mkskill "$repo/plugins/bar/skills/bar" bar "plugin-layout bar skill"
# duplicate name in a lower-precedence root
mkskill "$repo/plugins/foo/skills/foo" foo "plugin-layout foo duplicate"
# a copy hidden under .opsman must be ignored
mkskill "$repo/.opsman/worktrees/x/.claude/skills/ghost" ghost "must not appear"
# frontmatter without name: falls back to dir basename
mkdir -p "$repo/.agents/skills/noname"
printf -- '---\ndescription: nameless skill\n---\n' >"$repo/.agents/skills/noname/SKILL.md"

out=$("$SCRIPTS_DIR/discover.sh")

# every line is valid compact JSON with the contract keys
printf '%s\n' "$out" | jq -e 'has("name") and has("description") and has("skill_dir") and has("root") and has("precedence") and has("sha256")' >/dev/null \
  || fail "line missing contract keys"

printf '%s\n' "$out" | jq -e 'select(.name == "bar")' >/dev/null || fail "bar not found"
printf '%s\n' "$out" | jq -e 'select(.name == "noname")' >/dev/null || fail "basename fallback failed"
if printf '%s\n' "$out" | grep -q ghost; then
  fail ".opsman content leaked into discovery"
fi

# both foo candidates present, repo-local one has lower precedence number
foo_count=$(printf '%s\n' "$out" | jq -s '[.[] | select(.name == "foo")] | length')
assert_eq "$foo_count" 2 "foo candidates"
best=$(printf '%s\n' "$out" | jq -s '[.[] | select(.name == "foo")] | sort_by(.precedence)[0].description')
assert_eq "$best" '"repo-local foo skill"' "precedence order"

# extra root via OPSMAN_SKILL_PATH
mkskill "$sandbox/extra/baz" baz "extra-root baz skill"
out2=$(OPSMAN_SKILL_PATH=$sandbox/extra "$SCRIPTS_DIR/discover.sh")
printf '%s\n' "$out2" | jq -e 'select(.name == "baz")' >/dev/null || fail "OPSMAN_SKILL_PATH root ignored"

# description survives extraction
d=$(printf '%s\n' "$out" | jq -rs '[.[] | select(.name == "bar")][0].description')
assert_eq "$d" "plugin-layout bar skill" "description extraction"

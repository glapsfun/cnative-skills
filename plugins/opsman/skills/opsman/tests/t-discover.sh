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

# --- repo-scoped default vs OPSMAN_INCLUDE_GLOBAL=1 opt-in ---

# plant skills in every home-level root
mkskill "$HOME/.claude/skills/homeskill" homeskill "home personal skill"
mkskill "$HOME/.claude/plugins/cache/mp/plug/skills/cacheskill" cacheskill "plugin-cache skill"
mkskill "$HOME/.agents/skills/agentskill" agentskill "home agents skill"

# by default none of them are discovered
out3=$("$SCRIPTS_DIR/discover.sh")
for n in homeskill cacheskill agentskill; do
  if printf '%s\n' "$out3" | jq -e --arg n "$n" 'select(.name == $n)' >/dev/null 2>&1; then
    fail "global skill discovered without opt-in: $n"
  fi
done

# with the opt-in, all three appear
out4=$(OPSMAN_INCLUDE_GLOBAL=1 "$SCRIPTS_DIR/discover.sh")
for n in homeskill cacheskill agentskill; do
  printf '%s\n' "$out4" | jq -e --arg n "$n" 'select(.name == $n)' >/dev/null \
    || fail "global skill missing with opt-in: $n"
done

# repo-local beats global for the same name
mkskill "$HOME/.claude/skills/foo" foo "home foo duplicate"
best_g=$(OPSMAN_INCLUDE_GLOBAL=1 "$SCRIPTS_DIR/discover.sh" \
  | jq -s '[.[] | select(.name == "foo")] | sort_by(.precedence)[0].description')
assert_eq "$best_g" '"repo-local foo skill"' "repo beats global"

# global beats the built-in base team
mkskill "$HOME/.claude/skills/scout" scout "home scout override"
best_s=$(OPSMAN_INCLUDE_GLOBAL=1 "$SCRIPTS_DIR/discover.sh" \
  | jq -s '[.[] | select(.name == "scout")] | sort_by(.precedence)[0].description')
assert_eq "$best_s" '"home scout override"' "global beats base"

# OPSMAN_SKILL_PATH beats global roots (explicit beats implicit)
mkskill "$HOME/.claude/skills/baz" baz "home baz duplicate"
best_b=$(OPSMAN_INCLUDE_GLOBAL=1 OPSMAN_SKILL_PATH=$sandbox/extra "$SCRIPTS_DIR/discover.sh" \
  | jq -s '[.[] | select(.name == "baz")] | sort_by(.precedence)[0].description')
assert_eq "$best_b" '"extra-root baz skill"' "skill-path beats global"

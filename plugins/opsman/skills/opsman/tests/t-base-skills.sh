#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

# (a) bare repo, no user skills anywhere: the base team is still discovered
"$SCRIPTS_DIR/build-registry.sh"
reg=$repo/.opsman/registry
assert_eq "$(jq -r 'length' "$reg/skills.json")" 4 "bare-repo registry size"
for s in developer operator reviewer scout; do
  jq -e --arg n "$s" '.[] | select(.name == $n)' "$reg/skills.json" >/dev/null \
    || fail "base skill missing from registry: $s"
done
jq -e '.[] | select(.name == "scout") | .skill_dir | contains("/base-skills/scout")' \
  "$reg/skills.json" >/dev/null || fail "scout not sourced from base-skills"

# (b) a repo-local skill with the same name shadows the built-in
mkskill "$repo/.claude/skills/scout" scout "repo-local scout override"
"$SCRIPTS_DIR/build-registry.sh"
assert_eq \
  "$(jq -r '.[] | select(.name == "scout") | .description' "$reg/skills.json")" \
  "repo-local scout override" "shadowing"
assert_eq \
  "$(jq -r '[.[] | select(.name == "scout")] | length' "$reg/skills.json")" \
  1 "dedup kept one scout"

# (c) base root comes last: its precedence number is the highest emitted
max_prec=$(OPSMAN_SKILL_PATH=$sandbox/nonexistent "$SCRIPTS_DIR/discover.sh" \
  | jq -s 'max_by(.precedence)')
printf '%s' "$max_prec" | jq -e '.root | endswith("base-skills")' >/dev/null \
  || fail "base-skills is not the lowest-priority root"

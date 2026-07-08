#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

run_id=$("$SCRIPTS_DIR/init-run.sh" "fix the widget thing in kubernetes-helper" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
C=$SCRIPTS_DIR/classify.sh

# usage
assert_status 2 "$C"

# a registry so component hints can match skill names
mkdir -p "$repo/.claude/skills/kubernetes-helper"
printf -- '---\nname: kubernetes-helper\ndescription: helper skill\n---\n' \
  >"$repo/.claude/skills/kubernetes-helper/SKILL.md"
"$SCRIPTS_DIR/build-registry.sh"

"$C" --run "$run_id"
assert_file "$rd/problem.yaml"
assert_eq "$(jq -r '.goal' "$rd/problem.yaml")" "fix the widget thing in kubernetes-helper"
# keywords: lowercase words longer than 3 chars
jq -e '.keywords | index("widget")' "$rd/problem.yaml" >/dev/null || fail "keyword widget missing"
jq -e '.keywords | index("thing")' "$rd/problem.yaml" >/dev/null || fail "keyword thing missing"
jq -e '.keywords | index("fix") | not' "$rd/problem.yaml" >/dev/null || fail "short word leaked in"
# component hint from registry
jq -e '.affected_components | index("kubernetes-helper")' "$rd/problem.yaml" >/dev/null \
  || fail "component hint missing"
# scaffold satisfies the problem schema required keys
for k in goal domain keywords risk acceptance_criteria; do
  jq -e --arg k "$k" 'has($k)' "$rd/problem.yaml" >/dev/null || fail "missing key $k"
done

# rerun does not clobber; --force does
jq '.goal = "edited by analyst"' "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
"$C" --run "$run_id"
assert_eq "$(jq -r '.goal' "$rd/problem.yaml")" "edited by analyst" "no-clobber"
"$C" --run "$run_id" --force
assert_eq "$(jq -r '.goal' "$rd/problem.yaml")" "fix the widget thing in kubernetes-helper" "force rescaffold"

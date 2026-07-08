#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# shellcheck disable=SC2016  # backticks in template fixtures are literal text
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
R=$SCRIPTS_DIR/render-context.sh

run_id=$("$SCRIPTS_DIR/init-run.sh" "polish the flux widget" | tail -n 1)
rd=$repo/.opsman/runs/$run_id

# usage
assert_status 2 "$R"

# DISCOVERING renders the discoverer packet with the task substituted
out=$("$R" --run "$run_id")
assert_file "$rd/context/1-discoverer.md"
printf '%s\n' "$out" | grep -q 'polish the flux widget' || fail "TASK not substituted"
printf '%s\n' "$out" | grep -q 'DISCOVERING' || fail "STATUS not substituted"
# registry absent: entitled-but-missing source renders the marker
printf '%s\n' "$out" | grep -q '(not yet available)' || fail "missing-source marker absent"
if printf '%s\n' "$out" | grep -q '{{'; then
  fail "unsubstituted token leaked"
fi

# a state with no roles.tsv row prints the handoff instead
t2=$sandbox/mini.tsv
printf 'NOSUCHSTATE\tnobody\tTASK\n' >"$t2"
out2=$("$R" --run "$run_id" --table "$t2")
printf '%s\n' "$out2" | grep -q 'Opsman Handoff' || fail "handoff not printed for role-less state"

# entitlement violation: template asks for a token the role does not have
tmpl=$sandbox/templates
mkdir -p "$tmpl"
printf '# Rogue\n\n{{PLAN}}\n' >"$tmpl/discoverer.md"
assert_status 5 "$R" --run "$run_id" --templates "$tmpl"

# two tokens on one line
printf '# Rogue\n\n{{TASK}} {{STATUS}}\n' >"$tmpl/discoverer.md"
assert_status 5 "$R" --run "$run_id" --templates "$tmpl"

# unknown token is refused (not entitled for any role)
printf '# Rogue\n\n{{BOGUS}}\n' >"$tmpl/discoverer.md"
assert_status 5 "$R" --run "$run_id" --templates "$tmpl"

# literal non-token braces (e.g. Helm examples) pass through untouched
printf '# T\n\ncheck that `{{ .Values.image }}` resolves\n\n{{TASK}}\n' >"$tmpl/discoverer.md"
out3=$("$R" --run "$run_id" --templates "$tmpl")
printf '%s\n' "$out3" | grep -q '.Values.image' || fail "literal template braces mangled"
printf '%s\n' "$out3" | grep -q 'polish the flux widget' || fail "token after literal line not substituted"

# a token with surrounding text on the line fails loudly, never silently
printf '# T\n\nTask: {{TASK}}\n' >"$tmpl/discoverer.md"
assert_status 5 "$R" --run "$run_id" --templates "$tmpl"

# M3 evidence index renders command summaries, not raw file listings.
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned
mkdir -p "$repo/.claude/skills/foo"
printf -- '---\nname: foo\ndescription: foo execution skill\n---\n' \
  >"$repo/.claude/skills/foo/SKILL.md"
"$SCRIPTS_DIR/build-registry.sh"
run2=$("$SCRIPTS_DIR/init-run.sh" "collect evidence with foo" | tail -n 1)
rd2=$repo/.opsman/runs/$run2
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run2"
jq '.keywords = ["foo"] | .domain = "dev" | .risk = "low"
    | .acceptance_criteria = ["ok"]' "$rd2/problem.yaml" >"$rd2/problem.yaml.tmp"
mv "$rd2/problem.yaml.tmp" "$rd2/problem.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run2"
jq -n '{selected: [{skill: "foo", role: "primary", reason: "match"}]}' \
  >"$rd2/selected-skills.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event SkillsSelected
jq -n '{steps: [{id: "s1", uses: "foo", depends_on: [], risk: "R1", success: "ok"}]}' \
  >"$rd2/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event PlanCreated
jq -n '{checks: [{id: "c1", command: "true", expected_exit: 0}]}' >"$rd2/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run2" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run2" >/dev/null
"$SCRIPTS_DIR/collect-evidence.sh" --run "$run2" --kind step --id s1 --risk R0 --cwd . --command true >/dev/null
out4=$("$R" --run "$run2")
printf '%s\n' "$out4" | grep -q 'step s1: exit=0 command=true' \
  || fail "evidence index missing command summary"

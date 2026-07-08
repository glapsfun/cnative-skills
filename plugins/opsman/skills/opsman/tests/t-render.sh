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

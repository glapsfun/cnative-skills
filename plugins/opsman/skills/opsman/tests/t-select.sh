#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

mkskill "$repo/.claude/skills/fluxcd" fluxcd "Operate and troubleshoot flux helmrelease reconciliation"
mkskill "$repo/.claude/skills/webdesign" webdesign "Design pretty landing pages with css"
mkdir -p "$repo/.claude/skills/fluxcd/scripts"
printf '#!/bin/sh\n' >"$repo/.claude/skills/fluxcd/scripts/flux-validate.sh"
"$SCRIPTS_DIR/build-registry.sh"

run_id=$("$SCRIPTS_DIR/init-run.sh" --base worktree "fix the failing flux helmrelease" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
S=$SCRIPTS_DIR/select-skills.sh

# missing problem.yaml -> exit 5
assert_status 5 "$S" --run "$run_id"

jq -n '{goal: "restore flux reconciliation", domain: "ops",
        keywords: ["flux", "helmrelease", "reconciliation"], risk: "medium",
        tools: ["flux"], affected_components: [], file_patterns: ["*.yaml"],
        acceptance_criteria: ["validation passes"]}' >"$rd/problem.yaml"

"$S" --run "$run_id"
assert_file "$rd/candidates.json"

# the flux skill outranks the unrelated one, and scores are explainable
assert_eq "$(jq -r '.[0].name' "$rd/candidates.json")" fluxcd
top=$(jq -r '.[0].score' "$rd/candidates.json")
bottom=$(jq -r '.[1].score' "$rd/candidates.json")
awk -v a="$top" -v b="$bottom" 'BEGIN { exit !(a > b) }' || fail "fluxcd not ranked above webdesign"
jq -e '.[0].signals.description_match.matched | index("flux")' "$rd/candidates.json" >/dev/null \
  || fail "matched words not recorded"
# no ledger.jsonl in this fixture -> neutral prior, exactly 0.5
jq -e '.[0].signals.historical_success == {weight: 0.10, approved: 0, total: 0, rate: 0.5}' \
  "$rd/candidates.json" >/dev/null \
  || fail "historical_success signal wrong for no-ledger case"

# deterministic: rerun with --force is byte-identical
cp "$rd/candidates.json" "$sandbox/c1.json"
"$S" --run "$run_id" --force
cmp -s "$rd/candidates.json" "$sandbox/c1.json" || fail "not deterministic"

# refuses to rescore once a selection exists, unless --force
jq -n '{selected: [{skill: "fluxcd", role: "primary", reason: "matches"}]}' \
  >"$rd/selected-skills.yaml"
assert_status 3 "$S" --run "$run_id"
"$S" --run "$run_id" --force

# ...but regenerating a LOST candidates.json is recovery, not a rescore
rm "$rd/candidates.json"
"$S" --run "$run_id"
assert_file "$rd/candidates.json"

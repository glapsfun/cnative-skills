#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

# --- unit tests for lib/scope.sh -------------------------------------------
. "$SCRIPTS_DIR/lib/scope.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"

plan=$sandbox/plan.json

# unscoped plan: no patterns, and never any violations
jq -n '{steps: [{id: "s1", uses: "x", depends_on: [], risk: "R1", success: "ok"}]}' >"$plan"
assert_eq "$(scope_patterns "$plan")" "" "unscoped plan has no patterns"
printf 'x\n' >stray.txt
assert_eq "$(scope_violations "$repo" "$plan")" "" "unscoped plan never violates"
rm stray.txt

# missing plan file behaves as unscoped
assert_eq "$(scope_patterns "$sandbox/nope.json")" "" "missing plan is unscoped"

# scoped plan: union across steps; steps without the field contribute nothing
jq -n '{steps: [
  {id: "s1", uses: "x", depends_on: [], risk: "R1", success: "ok", allowed_files: ["src/*"]},
  {id: "s2", uses: "x", depends_on: [], risk: "R1", success: "ok"},
  {id: "s3", uses: "x", depends_on: [], risk: "R1", success: "ok", allowed_files: ["docs/notes.md"]}
]}' >"$plan"
assert_eq "$(scope_patterns "$plan" | sort | tr '\n' ' ')" "docs/notes.md src/* " "union of declared patterns"

# in-scope changes pass: tracked + untracked, and the glob crosses /
mkdir -p src/deep docs
printf 'a\n' >src/app.py
printf 'n\n' >src/deep/new.py
printf 'd\n' >docs/notes.md
assert_eq "$(scope_violations "$repo" "$plan")" "" "in-scope files pass (glob crosses /)"

# out-of-scope untracked file is reported
printf 'x\n' >rogue.txt
assert_eq "$(scope_violations "$repo" "$plan")" "rogue.txt" "out-of-scope file reported"
rm rogue.txt

# rename: BOTH sides must be in scope — the out-of-scope target is reported
git add src docs
git -c user.name=t -c user.email=t@t commit -qm base
git mv docs/notes.md rogue.md
assert_eq "$(scope_violations "$repo" "$plan")" "rogue.md" "rename target out of scope reported"
git reset --hard -q

#!/usr/bin/env bash
set -euo pipefail

# Failing-first test for sre-agent Crossplane expertise
# (task 20260720-give-sre-agent-crossplane-expertise-dete).
# Mirrors tests/sre-aws-discovery.test.sh; the full repo suite
# (scripts/check.sh --all) runs separately at VERIFY.

cd "$(git rev-parse --show-toplevel)"

# shellcheck source=tests/lib.sh
source tests/lib.sh

s=plugins/sre-agent/skills/sre-agent/scripts/crossplane-status-check.sh
ref=plugins/sre-agent/skills/sre-agent/references/crossplane-remediation.md

# --- files exist, tracked, executable -------------------------------------
git ls-files --error-unmatch "$s" >/dev/null 2>&1 || fail "$s not git-tracked"
git ls-files --error-unmatch "$ref" >/dev/null 2>&1 || fail "$ref not git-tracked"
test -x "$s" || fail "$s not executable"

# --- help contract ----------------------------------------------------------
help_out="$("$s" --help)" || fail "--help exited non-zero"
grep -qi "crossplane" <<<"$help_out" || fail "--help does not mention crossplane"
grep -q "TYPE" <<<"$help_out" || fail "--help does not document the TYPE[/NAME] argument"

# --- usage errors exit 2 ----------------------------------------------------
expect_exit2 "two positional args" "foo/bar" "extra"
expect_exit2 "unrecognized flag" --bogus

# --- environment errors exit 3, with a GAP: line ----------------------------
# /usr/bin:/bin has coreutils + bash but no kubectl on macOS/Linux defaults
rc=0
out="$(PATH=/usr/bin:/bin "$s" 2>&1)" || rc=$?
[[ $rc -eq 3 ]] || fail "missing kubectl should exit 3 (got $rc)"
grep -q "^GAP:" <<<"$out" || fail "missing kubectl should print a GAP: line"

# --- read-only guarantee ----------------------------------------------------
if grep -E '\b(kubectl|crossplane)\b[^|;]*\b(apply|create|delete|patch|edit|replace|scale|drain|cordon|annotate|label)\b' "$s"; then
  fail "script contains a mutating kubectl/crossplane verb"
fi

# --- reference doc covers the key safety mechanism --------------------------
grep -q "crossplane.io/paused" "$ref" || fail "$ref missing the crossplane.io/paused pause-annotation guidance"

# --- integration touchpoints ------------------------------------------------
skill=plugins/sre-agent/skills/sre-agent
grep -q "crossplane-status-check.sh" "$skill/SKILL.md" || fail "SKILL.md does not reference the script"
grep -q "crossplane-remediation.md" "$skill/SKILL.md" || fail "SKILL.md does not reference the reference doc"
grep -qi "crossplane" "$skill/references/remediation.md" || fail "remediation.md does not mention Crossplane"
grep -q "crossplane" "$skill/scripts/sre-env-discovery.sh" || fail "sre-env-discovery.sh does not detect crossplane"
grep -qi "crossplane" "$skill/evals/evals.json" || fail "evals.json has no crossplane eval"

# Manifest version parity is enforced repo-wide by scripts/checks/manifest-versions.sh.

echo "PASS: all crossplane-status-check assertions hold"

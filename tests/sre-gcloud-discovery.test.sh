#!/usr/bin/env bash
set -euo pipefail

# Failing-first test for the sre-agent gcloud discovery feature
# (task 20260717-add-read-only-gcloud-cli-discovery-searc).
# Mirrors the sddx oracle's behavioral assertions; the full repo suite
# (scripts/check.sh --all) runs separately at VERIFY.

cd "$(git rev-parse --show-toplevel)"

# shellcheck source=tests/lib.sh
source tests/lib.sh

s=plugins/sre-agent/skills/sre-agent/scripts/sre-gcloud-discovery.sh
ref=plugins/sre-agent/skills/sre-agent/references/gcloud-investigation.md

# --- files exist, tracked, executable -------------------------------------
git ls-files --error-unmatch "$s" >/dev/null 2>&1 || fail "$s not git-tracked"
git ls-files --error-unmatch "$ref" >/dev/null 2>&1 || fail "$ref not git-tracked"
test -x "$s" || fail "$s not executable"

# --- help contract --------------------------------------------------------
help_out="$("$s" --help)" || fail "--help exited non-zero"
for sub in env clusters timeline logs health; do
  grep -q "$sub" <<<"$help_out" || fail "--help does not mention subcommand: $sub"
done

# --- usage errors exit 2 --------------------------------------------------
expect_exit2 "no args"
expect_exit2 "unknown subcommand" bogus
expect_exit2 "non-ISO since-date" timeline my-proj 07/01/2026
expect_exit2 "invalid project id" logs "my proj" error

# --- GAP degradation: gcloud absent → GAP: line, exit 0 -------------------
run_without_gcloud() {
  # /usr/bin:/bin has coreutils + bash but no gcloud on macOS/Linux defaults
  PATH=/usr/bin:/bin "$s" "$@"
}
for args in "env" "clusters" "timeline my-proj 2026-07-01" "logs my-proj error" "health my-proj"; do
  # shellcheck disable=SC2086  # word-splitting of $args is the point here
  out="$(run_without_gcloud $args)" || fail "'$args' without gcloud should exit 0"
  grep -q "^GAP:" <<<"$out" || fail "'$args' without gcloud should print a GAP: line"
done

# --- read-only guarantee --------------------------------------------------
if grep -E 'gcloud[^|;]*\b(update|create|delete|patch|apply|set-iam-policy|add-iam-policy-binding|remove-iam-policy-binding|resize|upgrade)\b' "$s"; then
  fail "script contains a mutating gcloud verb"
fi

# --- untrusted-content markers --------------------------------------------
grep -q "BEGIN EXTERNAL DATA" "$s" || fail "script missing EXTERNAL DATA markers"

# --- integration touchpoints ----------------------------------------------
skill=plugins/sre-agent/skills/sre-agent
grep -q "sre-gcloud-discovery.sh" "$skill/SKILL.md" || fail "SKILL.md does not reference the script"
grep -q "gcloud-investigation.md" "$skill/SKILL.md" || fail "SKILL.md does not reference the reference doc"
grep -q "sre-gcloud-discovery.sh" "$skill/references/investigators/gke.md" || fail "gke.md does not reference the script"
grep -q "sre-gcloud-discovery.sh" "$skill/references/investigators/changes.md" || fail "changes.md does not reference the script"
grep -q "sre-gcloud-discovery.sh" "$skill/evals/evals.json" || fail "evals.json has no gcloud-discovery eval"

# Manifest version parity is enforced repo-wide by scripts/checks/manifest-versions.sh.

echo "PASS: all sre-gcloud-discovery assertions hold"

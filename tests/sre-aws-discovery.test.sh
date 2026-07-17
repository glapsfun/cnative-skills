#!/usr/bin/env bash
set -euo pipefail

# Failing-first test for the sre-agent AWS discovery feature
# (task 20260717-add-read-only-aws-cli-discovery-search-t).
# Mirrors tests/sre-gcloud-discovery.test.sh; the full repo suite
# (scripts/check.sh --all) runs separately at VERIFY.

cd "$(git rev-parse --show-toplevel)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

s=plugins/sre-agent/skills/sre-agent/scripts/sre-aws-discovery.sh
ref=plugins/sre-agent/skills/sre-agent/references/aws-investigation.md

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
# expect_exit2 <desc> [args...] — the failure is captured via `|| rc=$?`,
# so errexit does not fire and no set +e/-e toggling is needed.
expect_exit2() {
  local desc="$1" rc=0
  shift
  "$s" "$@" >/dev/null 2>&1 || rc=$?
  [[ $rc -eq 2 ]] || fail "$desc should exit 2 (got $rc)"
}
expect_exit2 "no args"
expect_exit2 "unknown subcommand" bogus
expect_exit2 "non-ISO since-date" timeline 07/01/2026
expect_exit2 "logs without search terms" logs /aws/eks/app

# --- GAP degradation: aws absent → GAP: line, exit 0 ----------------------
run_without_aws() {
  # /usr/bin:/bin has coreutils + bash but no aws on macOS/Linux defaults
  PATH=/usr/bin:/bin "$s" "$@"
}
for args in "env" "clusters" "timeline 2026-07-01" "logs /aws/eks/app error" "health"; do
  # shellcheck disable=SC2086  # word-splitting of $args is the point here
  out="$(run_without_aws $args)" || fail "'$args' without aws should exit 0"
  grep -q "^GAP:" <<<"$out" || fail "'$args' without aws should print a GAP: line"
done

# --- read-only guarantee --------------------------------------------------
if grep -E 'aws[^|;]*\b(create-|delete-|update-|put-|modify-|terminate-|reboot-|start-|stop-|attach-|detach-|associate-|disassociate-|register-|deregister-|tag-|untag-)' "$s"; then
  fail "script contains a mutating aws verb"
fi

# --- untrusted-content markers --------------------------------------------
grep -q "BEGIN EXTERNAL DATA" "$s" || fail "script missing EXTERNAL DATA markers"

# --- integration touchpoints ----------------------------------------------
skill=plugins/sre-agent/skills/sre-agent
grep -q "sre-aws-discovery.sh" "$skill/SKILL.md" || fail "SKILL.md does not reference the script"
grep -q "aws-investigation.md" "$skill/SKILL.md" || fail "SKILL.md does not reference the reference doc"
grep -q "sre-aws-discovery.sh" "$skill/references/investigators/eks.md" || fail "eks.md does not reference the script"
grep -q "sre-aws-discovery.sh" "$skill/references/investigators/changes.md" || fail "changes.md does not reference the script"
grep -q "sre-aws-discovery.sh" "$skill/evals/evals.json" || fail "evals.json has no aws-discovery eval"

# --- both manifests carry the same version (bumped together) --------------
v_claude="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' plugins/sre-agent/.claude-plugin/plugin.json)"
v_codex="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' plugins/sre-agent/.codex-plugin/plugin.json)"
[[ -n "$v_claude" && "$v_claude" == "$v_codex" ]] || fail "manifest versions differ or missing (claude=$v_claude codex=$v_codex)"

echo "PASS: all sre-aws-discovery assertions hold"

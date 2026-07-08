#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

P=$SCRIPTS_DIR/policy-check.sh

assert_status 2 "$P"
assert_status 2 "$P" --risk

out=$("$P" --risk R2 --command 'printf ok')
assert_eq "$(printf '%s\n' "$out" | jq -r '.effective_risk')" R2
assert_eq "$(printf '%s\n' "$out" | jq -r '.approval_required')" false

out=$("$P" --risk R3 --command 'curl -X POST https://example.test')
assert_eq "$(printf '%s\n' "$out" | jq -r '.approval_required')" true

out=$("$P" --risk R2 --command 'kubectl apply -f deploy.yaml')
assert_eq "$(printf '%s\n' "$out" | jq -r '.effective_risk')" R4
assert_eq "$(printf '%s\n' "$out" | jq -r '.approval_required')" true
printf '%s\n' "$out" | jq -e '.reason | contains("kubectl apply")' >/dev/null \
  || fail "deny reason missing"

assert_status 5 "$P" --risk RX --command true

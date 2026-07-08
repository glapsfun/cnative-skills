#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

P=$SCRIPTS_DIR/check-plan.sh

# usage / missing file
assert_status 2 "$P"
assert_status 5 "$P" "$sandbox/nope.json"

good=$sandbox/good.json
jq -n '{steps: [
  {id: "inspect", uses: "sre-agent", depends_on: [], risk: "R0", success: "baseline recorded"},
  {id: "fix", uses: "fluxcd", depends_on: ["inspect"], risk: "R2", success: "validator passes"},
  {id: "verify", uses: "fluxcd", depends_on: ["fix"], risk: "R0", success: "all checks green"}
]}' >"$good"
"$P" "$good"

# duplicate id
jq '.steps[1].id = "inspect"' "$good" >"$sandbox/dup.json"
assert_status 5 "$P" "$sandbox/dup.json"

# unknown dependency
jq '.steps[1].depends_on = ["ghost"]' "$good" >"$sandbox/ghost.json"
assert_status 5 "$P" "$sandbox/ghost.json"

# cycle
jq '.steps[0].depends_on = ["verify"]' "$good" >"$sandbox/cycle.json"
assert_status 5 "$P" "$sandbox/cycle.json"

# bad risk class
jq '.steps[0].risk = "R9"' "$good" >"$sandbox/risk.json"
assert_status 5 "$P" "$sandbox/risk.json"

# missing required field
jq 'del(.steps[0].success)' "$good" >"$sandbox/nosucc.json"
assert_status 5 "$P" "$sandbox/nosucc.json"

# empty steps
jq -n '{steps: []}' >"$sandbox/empty.json"
assert_status 5 "$P" "$sandbox/empty.json"

#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

T=$SCRIPTS_DIR/transition.sh

assert_eq "$("$T" DISCOVERING SkillsIndexed)" UNDERSTANDING
assert_eq "$("$T" PLANNING PlanCreated)" TEST_DESIGN
assert_eq "$("$T" REPLANNING PlanCreated)" TEST_DESIGN
assert_eq "$("$T" TEST_DESIGN BaselineRecorded)" IMPLEMENTING
assert_eq "$("$T" JUDGING OracleApproved)" COMPLETED

# wildcard rows apply from any state
assert_eq "$("$T" IMPLEMENTING BudgetExceeded)" BLOCKED
assert_eq "$("$T" SELECTING HumanApprovalRequired)" WAITING_APPROVAL

# @return passes through for the approval round-trip
assert_eq "$("$T" WAITING_APPROVAL ApprovalGranted)" "@return"

# illegal transition: exit 3
assert_status 3 "$T" PLANNING OracleApproved
# ...and the error names the legal events
set +e
err=$("$T" PLANNING OracleApproved 2>&1)
set -e
case $err in
  *PlanCreated*) : ;;
  *) fail "error should list legal events, got: $err" ;;
esac

# usage error: exit 2
assert_status 2 "$T" PLANNING

# terminal states accept no events, not even wildcard rows
assert_status 3 "$T" COMPLETED RunAbandoned
assert_status 3 "$T" ABANDONED HumanApprovalRequired
# BLOCKED is not terminal: abandon is still legal there
assert_eq "$("$T" BLOCKED RunAbandoned)" ABANDONED

#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

# die exits with the given code and prints an opsman: prefix to stderr
set +e
msg=$(sh -c ". '$SCRIPTS_DIR/lib/common.sh'; die 7 boom" 2>&1)
code=$?
set -e
assert_eq "$code" 7 "die exit code"
assert_eq "$msg" "opsman: boom" "die message"

# need_cmd: exit 7 for a command that cannot exist
assert_status 7 sh -c ". '$SCRIPTS_DIR/lib/common.sh'; need_cmd definitely-not-a-cmd-xyz"

# sha256_file: known digest of the string "x"
printf 'x' >"$sandbox/f"
h=$(sh -c ". '$SCRIPTS_DIR/lib/common.sh'; sha256_file '$sandbox/f'")
assert_eq "$h" "2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881" "sha256"

# utc_now: ISO-8601 Zulu shape
now=$(sh -c ". '$SCRIPTS_DIR/lib/common.sh'; utc_now")
case $now in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
  *) fail "utc_now shape: $now" ;;
esac

# paths.sh: OPSMAN_ROOT resolves to the git toplevel
repo=$(mkrepo)
root=$(cd "$repo" && sh -c ". '$SCRIPTS_DIR/lib/paths.sh'; printf %s \"\$OPSMAN_ROOT\"")
# macOS mktemp puts sandboxes under /private; compare resolved paths
assert_eq "$(cd "$root" && pwd -P)" "$(cd "$repo" && pwd -P)" "OPSMAN_ROOT"

# json.sh: schema_check passes when required keys exist, fails when missing
printf '{"required":["a","b"]}\n' >"$sandbox/schema.json"
printf '{"a":1,"b":2}\n' >"$sandbox/good.json"
printf '{"a":1}\n' >"$sandbox/bad.json"
sh -c ". '$SCRIPTS_DIR/lib/common.sh'; . '$SCRIPTS_DIR/lib/json.sh'; schema_check '$sandbox/schema.json' '$sandbox/good.json'" || fail "schema_check good"
assert_status 1 sh -c ". '$SCRIPTS_DIR/lib/common.sh'; . '$SCRIPTS_DIR/lib/json.sh'; schema_check '$sandbox/schema.json' '$sandbox/bad.json'"

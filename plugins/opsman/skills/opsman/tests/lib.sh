# shellcheck shell=sh
# shellcheck disable=SC2034  # SCRIPTS_DIR is consumed by the sourcing t-*.sh
# Shared helpers for opsman kernel tests. Source from t-*.sh.
set -eu

TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS_DIR=$TESTS_DIR/../scripts

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# Isolate from the developer's machine: empty HOME, no extra skill roots.
HOME=$sandbox/home
export HOME
mkdir -p "$HOME"
unset OPSMAN_SKILL_PATH OPSMAN_ROOT 2>/dev/null || true

mkrepo() {
  _r=$sandbox/repo
  mkdir -p "$_r"
  git -C "$_r" init -q
  git -C "$_r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  printf '%s\n' "$_r"
}

mkskill() { # dir name description — SKILL.md fixture matching the discoverer contract
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: %s\n---\n\nbody\n' "$2" "$3" >"$1/SKILL.md"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() { # actual expected [label]
  [ "$1" = "$2" ] || fail "expected [$2], got [$1] ${3:-}"
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_status() { # expected_code cmd [args...]
  _want=$1
  shift
  set +e
  "$@" >/dev/null 2>&1
  _got=$?
  set -e
  [ "$_got" -eq "$_want" ] || fail "expected exit $_want, got $_got: $*"
}

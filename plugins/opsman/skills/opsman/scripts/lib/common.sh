# shellcheck shell=sh
# shellcheck disable=SC2034  # exit-code constants are consumed by sourcing scripts
# Shared helpers for all opsman scripts. POSIX sh only.

EX_OK=0
EX_USAGE=2
EX_STATE=3
EX_LOCK=4
EX_ARTIFACT=5
EX_BUDGET=6
EX_DEP=7

die() {
  _die_code=$1
  shift
  printf 'opsman: %s\n' "$*" >&2
  exit "$_die_code"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$EX_DEP" "required command not found: $1"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "$EX_DEP" "no sha256 tool found (need sha256sum or shasum)"
  fi
}

utc_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

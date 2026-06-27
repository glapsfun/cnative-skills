#!/usr/bin/env bash
#
# bash-version-check.sh — report the shell toolchain and target environment.
#
# Read-only. Detects the running bash version, the OS/userland (GNU vs BSD),
# and whether the common shell-quality tools are installed, so version- and
# platform-sensitive advice can be matched to reality instead of assumed.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [-h|--help]

Reports bash version, OS/userland, and availability of shellcheck, shfmt,
bats, and checkbashisms. Read-only; makes no changes.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

section() { printf '\n## %s\n' "$1"; }

tool_status() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    local ver
    ver="$("${name}" --version 2>/dev/null | head -n1 || true)"
    printf '  %-14s installed%s\n' "${name}" "${ver:+ (${ver})}"
  else
    printf '  %-14s MISSING\n' "${name}"
  fi
}

section "Running shell"
printf '  bash version: %s\n' "${BASH_VERSION:-unknown}"
if [[ -n "${BASH_VERSINFO:-}" ]]; then
  if ((BASH_VERSINFO[0] < 4)); then
    # shellcheck disable=SC2016  # ${var^^} is literal documentation text, not an expansion
    printf '  NOTE: bash %s is pre-4.0 — no associative arrays, ${var^^}, or mapfile.\n' "${BASH_VERSINFO[0]}"
    printf '        On macOS, install a modern bash with: brew install bash\n'
  fi
fi
printf '  /bin/sh -> %s\n' "$(readlink /bin/sh 2>/dev/null || echo '/bin/sh (not a symlink)')"

section "Operating system / userland"
os="$(uname -s 2>/dev/null || echo unknown)"
printf '  uname: %s\n' "${os}"
case "${os}" in
  Linux) printf '  userland: GNU coreutils expected (long flags, sed -i in place).\n' ;;
  Darwin) printf '  userland: BSD (macOS) — sed -i needs an arg, no readlink -f, date -v.\n' ;;
  *BSD) printf '  userland: BSD — expect BSD-flavored coreutils.\n' ;;
  *) printf '  userland: unrecognized — verify tool flags before relying on them.\n' ;;
esac

section "Shell quality tooling"
tool_status shellcheck
tool_status shfmt
tool_status bats
tool_status checkbashisms

section "Summary"
missing=()
for t in shellcheck shfmt bats; do
  command -v "${t}" >/dev/null 2>&1 || missing+=("${t}")
done
if ((${#missing[@]} == 0)); then
  echo "  All core tools present — you can lint, format, and test locally."
else
  printf '  Missing: %s\n' "$(
    IFS=' '
    echo "${missing[*]}"
  )"
  echo "  Install (macOS): brew install shellcheck shfmt bats-core"
  echo "  Install (Debian/Ubuntu): apt-get install shellcheck shfmt bats"
fi

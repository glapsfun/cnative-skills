#!/usr/bin/env bash
#
# bash-doc-discover.sh — print authoritative shell-scripting documentation links.
#
# Use when refreshing this skill or when you need a canonical reference for a
# behavior that may be version-sensitive. Prefer these primary sources over
# memory for exact flag names, builtin behavior, and ShellCheck rationale.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [-h|--help]

Print curated, authoritative documentation links for Bash, POSIX shell,
ShellCheck, shfmt, and Bats. Read-only; prints to stdout.
Accepts no arguments, or exactly one -h/--help option.
EOF
}

if (($# > 0)); then
  if (($# == 1)) && [[ $1 == "-h" || $1 == "--help" ]]; then
    usage
    exit 0
  fi

  unexpected_argument=$1
  if [[ $1 == "-h" || $1 == "--help" ]]; then
    unexpected_argument=$2
  fi
  printf 'error: unexpected argument: %s\n' "${unexpected_argument}" >&2
  exit 2
fi

cat <<'DOCS'
## Bash (the language)
- GNU Bash Reference Manual:        https://www.gnu.org/software/bash/manual/bash.html
- Bash manual (parameter expansion): https://www.gnu.org/software/bash/manual/bash.html#Shell-Parameter-Expansion
- Bash Hackers Wiki (archived):     https://web.archive.org/web/2023/https://wiki.bash-hackers.org/
- Greg's Wiki (BashGuide):          https://mywiki.wooledge.org/BashGuide
- Greg's Wiki (BashFAQ):            https://mywiki.wooledge.org/BashFAQ
- Greg's Wiki (BashPitfalls):       https://mywiki.wooledge.org/BashPitfalls

## POSIX shell
- POSIX Shell Command Language:     https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html
- Dash (POSIX sh) manual:           https://manpages.debian.org/dash

## Static analysis & formatting
- ShellCheck wiki (all SC codes):   https://www.shellcheck.net/wiki/
- ShellCheck (look up a code):      https://www.shellcheck.net/wiki/SC2086
- shfmt (mvdan/sh):                 https://github.com/mvdan/sh
- checkbashisms (devscripts):       https://manpages.debian.org/checkbashisms

## Testing
- Bats-core:                        https://bats-core.readthedocs.io/
- bats-assert / bats-support:       https://github.com/bats-core/bats-assert
- shunit2:                          https://github.com/kward/shunit2

## Style guides
- Google Shell Style Guide:         https://google.github.io/styleguide/shellguide.html
DOCS

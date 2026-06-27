#!/usr/bin/env bash
#
# bash-lint.sh — one-command quality gate for shell scripts.
#
# Chains the three checks every script should pass before it ships:
#   1. bash -n     syntax check (always available)
#   2. shellcheck  static analysis for correctness bugs (if installed)
#   3. shfmt -d    formatting diff (if installed)
#
# Missing optional tools are reported and skipped, not treated as failures,
# so the script is useful even on a bare machine. Exits non-zero if any
# available check fails, making it safe to wire into CI or a pre-commit hook.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] <file-or-dir> [more...]

Run bash -n, shellcheck, and shfmt against the given shell scripts.
Directories are searched recursively for *.sh files.

Options:
  --no-shellcheck   Skip the shellcheck stage
  --no-shfmt        Skip the shfmt stage
  --fix             With shfmt available, rewrite files in place (shfmt -w)
  -h, --help        Show this help and exit

Exit status: 0 if all run checks pass, 1 otherwise.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 2
}

collect_scripts() {
  # Print NUL-delimited list of scripts from the given paths.
  local path
  for path in "$@"; do
    if [[ -d "${path}" ]]; then
      find "${path}" -type f -name '*.sh' -print0
    elif [[ -f "${path}" ]]; then
      printf '%s\0' "${path}"
    else
      die "no such file or directory: ${path}"
    fi
  done
}

main() {
  local run_shellcheck=1 run_shfmt=1 fix=0
  local -a paths=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-shellcheck)
        run_shellcheck=0
        shift
        ;;
      --no-shfmt)
        run_shfmt=0
        shift
        ;;
      --fix)
        fix=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          paths+=("$1")
          shift
        done
        ;;
      -*) die "unknown option: $1" ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  ((${#paths[@]} >= 1)) || {
    usage
    die "no files or directories given"
  }

  # Tool availability.
  local have_shellcheck=0 have_shfmt=0
  command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1
  command -v shfmt >/dev/null 2>&1 && have_shfmt=1
  ((run_shellcheck && !have_shellcheck)) && log "note: shellcheck not installed — skipping (brew install shellcheck)"
  ((run_shfmt && !have_shfmt)) && log "note: shfmt not installed — skipping (brew install shfmt)"

  # Gather target scripts safely (NUL-delimited).
  local -a scripts=()
  while IFS= read -r -d '' f; do
    scripts+=("${f}")
  done < <(collect_scripts "${paths[@]}")

  ((${#scripts[@]} >= 1)) || die "no *.sh files found in the given paths"

  local failures=0 script
  for script in "${scripts[@]}"; do
    log "==> ${script}"

    if ! bash -n "${script}"; then
      log "  [FAIL] bash -n (syntax)"
      ((failures++))
      continue
    fi
    log "  [ok]   bash -n"

    if ((run_shellcheck && have_shellcheck)); then
      if shellcheck "${script}"; then
        log "  [ok]   shellcheck"
      else
        log "  [FAIL] shellcheck"
        ((failures++))
      fi
    fi

    if ((run_shfmt && have_shfmt)); then
      if ((fix)); then
        shfmt -i 2 -ci -w "${script}" && log "  [ok]   shfmt -w (formatted)"
      elif shfmt -i 2 -ci -d "${script}"; then
        log "  [ok]   shfmt (formatted)"
      else
        log "  [FAIL] shfmt — run with --fix or 'shfmt -i 2 -ci -w'"
        ((failures++))
      fi
    fi
  done

  log ""
  if ((failures == 0)); then
    log "All checks passed (${#scripts[@]} file(s))."
    return 0
  fi
  log "${failures} check(s) failed across ${#scripts[@]} file(s)."
  return 1
}

main "$@"

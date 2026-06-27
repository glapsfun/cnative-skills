#!/usr/bin/env bash
#
# bash-scaffold.sh — print a production-ready bash script skeleton to stdout.
#
# Emits strict mode, a usage/--help, a manual long-option parser with `--`
# handling, leveled logging to stderr, a trap-based cleanup handler, and a
# `main "$@"` source-guard so the result is testable with Bats. Redirect to a
# file and edit the marked sections:
#
#   bash bash-scaffold.sh --name deploy --description "Deploy the app" > deploy.sh

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Print a strict-mode bash script template to stdout.

Options:
  -n, --name NAME           Script name shown in usage (default: my-script)
  -d, --description TEXT    One-line description for the header
  -h, --help                Show this help and exit
EOF
}

main() {
  local name="my-script" description="One-line description of what this does."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n | --name)
        name="${2:?--name needs a value}"
        shift 2
        ;;
      -d | --description)
        description="${2:?--description needs a value}"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'error: unknown option: %s\n' "$1" >&2
        exit 2
        ;;
      *) break ;;
    esac
  done

  # Header is dynamic (name/description); the body is emitted verbatim from a
  # quoted heredoc so none of its $variables expand here.
  printf '#!/usr/bin/env bash\n'
  printf '#\n'
  printf '# %s — %s\n' "${name}" "${description}"
  printf '#\n\n'

  cat <<'TEMPLATE'
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=SC2034  # SCRIPT_DIR is here for your code to reference sibling files
readonly SCRIPT_DIR
readonly SCRIPT_NAME="${0##*/}"

# --- logging (to stderr; stdout stays reserved for real output) -------------
log() { printf '%s [%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$1" "${*:2}" >&2; }
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
die() {
  log_error "$@"
  exit 1
}

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} [OPTIONS] <arg>

Options:
  -v, --verbose   Enable verbose logging
  -n, --dry-run   Print actions without executing them
  -h, --help      Show this help and exit
USAGE
}

# --- cleanup: runs on every exit path, preserving the original exit code ----
cleanup() {
  local rc=$?
  # TODO: remove temp files / kill background jobs here.
  trap - EXIT
  exit "${rc}"
}
trap cleanup EXIT
trap 'die "interrupted"' INT TERM

# Wrap mutating commands so --dry-run can short-circuit them.
DRY_RUN=0
run() {
  if ((DRY_RUN)); then
    printf 'DRY-RUN: %s\n' "$*" >&2
  else
    "$@"
  fi
}

main() {
  local verbose=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v | --verbose)
        verbose=1
        shift
        ;;
      -n | --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage >&2
        die "unknown option: $1"
        ;;
      *) break ;;
    esac
  done

  (($# >= 1)) || {
    usage >&2
    exit 2
  }
  ((verbose)) && log_info "verbose mode on"

  local target="$1"

  # TODO: real work goes here. Validate inputs first, e.g.:
  #   command -v jq >/dev/null 2>&1 || die "jq is required"
  #   [[ -r "${target}" ]] || die "cannot read: ${target}"

  log_info "done: ${target}"
}

# Only run main when executed, not when sourced (so functions are unit-testable).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
TEMPLATE
}

main "$@"

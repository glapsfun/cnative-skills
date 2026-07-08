# shellcheck shell=sh
# Logging helpers: everything to stderr, opsman: prefix.

log_info() { printf 'opsman: %s\n' "$*" >&2; }
log_warn() { printf 'opsman: warning: %s\n' "$*" >&2; }
log_error() { printf 'opsman: error: %s\n' "$*" >&2; }

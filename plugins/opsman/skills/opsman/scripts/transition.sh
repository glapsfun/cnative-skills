#!/bin/sh
# Pure transition lookup: current state + event -> next state (or exit 3).
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/state.sh"

usage() {
  printf 'usage: transition.sh [--table <tsv>] <current-state> <event>\n' >&2
}

table=$SCRIPT_DIR/state-machine.tsv
if [ "${1:-}" = "--table" ]; then
  table=$2
  shift 2
fi
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac
if [ $# -ne 2 ]; then
  usage
  exit "$EX_USAGE"
fi

nxt=$(next_state "$table" "$1" "$2")
if [ -z "$nxt" ]; then
  die "$EX_STATE" "illegal transition: $1 + $2 (legal events: $(legal_events "$table" "$1" | tr '\n' ' '))"
fi
printf '%s\n' "$nxt"

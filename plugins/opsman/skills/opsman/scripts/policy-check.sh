#!/bin/sh
# Computes effective command risk from declared risk plus deny patterns.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"

usage() {
  printf 'usage: policy-check.sh --risk R0|R1|R2|R3|R4 --command <command>\n' >&2
}

risk=''
cmd=''
while [ $# -gt 0 ]; do
  case $1 in
    --risk)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      risk=$2
      shift 2
      ;;
    --command)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      cmd=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit "$EX_USAGE"
      ;;
  esac
done
[ -n "$risk" ] && [ -n "$cmd" ] || {
  usage
  exit "$EX_USAGE"
}
case $risk in
  R0 | R1 | R2 | R3 | R4) ;;
  *) die "$EX_ARTIFACT" "invalid risk: $risk" ;;
esac

need_cmd jq

effective=$risk
reason='declared risk within automatic policy'
cmd_lc=$(printf '%s\n' "$cmd" | tr '[:upper:]' '[:lower:]')
while IFS= read -r pattern || [ -n "$pattern" ]; do
  [ -n "$pattern" ] || continue
  pat_lc=$(printf '%s\n' "$pattern" | tr '[:upper:]' '[:lower:]')
  case $cmd_lc in
    *"$pat_lc"*)
      effective=R4
      reason="deny pattern matched: $pattern"
      break
      ;;
  esac
done <"$SCRIPT_DIR/policy.deny"

approval=false
case $effective in
  R3 | R4) approval=true ;;
esac

jq -n --arg declared_risk "$risk" --arg effective_risk "$effective" \
  --argjson approval_required "$approval" --arg reason "$reason" \
  '{declared_risk: $declared_risk, effective_risk: $effective_risk,
    approval_required: $approval_required, reason: $reason}'

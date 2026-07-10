#!/bin/sh
# Renders the context packet for the role that owns the run's current state.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/state.sh"

usage() {
  printf 'usage: render-context.sh --run <run-id> [--table <tsv>] [--templates <dir>]\n' >&2
}

run_id=''
roles_table=$SCRIPT_DIR/roles.tsv
templates_dir=$SCRIPT_DIR/../agents
while [ $# -gt 0 ]; do
  case $1 in
    --run)
      run_id=$2
      shift 2
      ;;
    --table)
      roles_table=$2
      shift 2
      ;;
    --templates)
      templates_dir=$2
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
if [ -z "$run_id" ]; then
  usage
  exit "$EX_USAGE"
fi

need_cmd jq
run_dir=$OPSMAN_RUNS_DIR/$run_id
[ -f "$run_dir/state.json" ] || die "$EX_ARTIFACT" "no such run: $run_id"

status_seq=$(jq -r '"\(.status) \(.seq)"' "$run_dir/state.json")
status=${status_seq% *}
seq_now=${status_seq#* }
role=$(role_for_state "$roles_table" "$status")
if [ -z "$role" ]; then
  # Resting states have no role: hand off instead of rendering.
  cat "$run_dir/handoff.md"
  exit 0
fi
allowed=",$(awk -F '\t' -v s="$status" '$1 == s { print $3; exit }' "$roles_table"),"

template=$templates_dir/$role.md
[ -f "$template" ] || die "$EX_STATE" "no template for role: $role ($template)"

emit_file() {
  if [ -f "$1" ]; then
    cat "$1"
  else
    printf '(not yet available)\n'
  fi
}

emit_token() {
  case $1 in
    TASK) jq -r '.task.raw_input' "$run_dir/state.json" ;;
    STATUS) printf '%s\n' "$status" ;;
    CAPABILITY_MAP) emit_file "$OPSMAN_REGISTRY_DIR/capability-map.md" ;;
    PROBLEM) emit_file "$run_dir/problem.yaml" ;;
    CANDIDATES)
      if [ -f "$run_dir/candidates.json" ]; then
        jq -r '.[] | "- \(.name)  score=\(.score)  (\(.skill_dir))"' "$run_dir/candidates.json"
      else
        printf '(not yet available)\n'
      fi
      ;;
    SELECTED) emit_file "$run_dir/selected-skills.yaml" ;;
    PLAN) emit_file "$run_dir/plan.yaml" ;;
    ACCEPTANCE) emit_file "$run_dir/acceptance.yaml" ;;
    EVIDENCE_INDEX)
      if [ -n "$(find "$run_dir/evidence" -mindepth 2 -maxdepth 2 -name meta.json 2>/dev/null | head -n 1)" ]; then
        find "$run_dir/evidence" -mindepth 2 -maxdepth 2 -name meta.json | LC_ALL=C sort \
          | while IFS= read -r meta; do
            jq -r --arg p "$(dirname "$meta")" \
              '"- \(.kind) \(.id): exit=\(.exit_code) command=\(.command) evidence=\($p)"' "$meta"
          done
      else
        printf '(not yet available)\n'
      fi
      ;;
    DIFF)
      wt=$(jq -r '.worktree.path // empty' "$run_dir/state.json")
      if [ -n "$wt" ] && [ -d "$wt" ]; then
        # Plain `git diff` hides untracked files; list them so a new-files-only
        # implementation does not render as "no change was made".
        git -C "$wt" status --porcelain --untracked-files=all
        git -C "$wt" diff --stat
        git -C "$wt" diff -- .
      else
        printf '(not yet available)\n'
      fi
      ;;
    *) die "$EX_ARTIFACT" "unknown token: {{$1}} in $template" ;;
  esac
}

mkdir -p "$run_dir/context"
packet=$run_dir/context/$seq_now-$role.md
trap 'rm -f "$packet.tmp"' EXIT

{
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      *'{{'*)
        if printf '%s\n' "$line" | grep -q '{{[A-Z_][A-Z_0-9]*}}'; then
          # A substitution token must be alone on its line — anything else
          # (label prefixes, two tokens) fails loudly instead of corrupting
          # the packet silently.
          tok=$(printf '%s\n' "$line" \
            | sed -n 's/^[[:space:]]*{{\([A-Z_][A-Z_0-9]*\)}}[[:space:]]*$/\1/p')
          [ -n "$tok" ] || die "$EX_ARTIFACT" "template error: a {{TOKEN}} must be alone on its line in $template: $line"
          case $allowed in
            *",$tok,"*) emit_token "$tok" ;;
            *) die "$EX_ARTIFACT" "entitlement violation: role $role may not use {{$tok}} in state $status" ;;
          esac
        else
          # Literal braces (e.g. a Helm '{{ .Values.x }}' example) pass through.
          printf '%s\n' "$line"
        fi
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$template"
} >"$packet.tmp"
mv "$packet.tmp" "$packet"

log_info "packet: $packet (role $role, state $status)"
cat "$packet"

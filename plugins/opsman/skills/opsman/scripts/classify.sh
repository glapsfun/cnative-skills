#!/bin/sh
# Scaffolds runs/<id>/problem.yaml for the analyst (JSON body; JSON is valid YAML).
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"

usage() {
  printf 'usage: classify.sh --run <run-id> [--force]\n' >&2
}

run_id=''
force=0
while [ $# -gt 0 ]; do
  case $1 in
    --run)
      run_id=$2
      shift 2
      ;;
    --force)
      force=1
      shift
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

out=$run_dir/problem.yaml
if [ -f "$out" ] && [ "$force" -ne 1 ]; then
  log_info "problem.yaml already exists (use --force to rescaffold): $out"
  exit 0
fi

task=$(jq -r '.task.raw_input' "$run_dir/state.json")

# Keyword hints: lowercase task words longer than 3 chars, deduped.
kw=$(printf '%s\n' "$task" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '\n' \
  | awk 'length($0) > 3' | LC_ALL=C sort -u | jq -Rn '[inputs]')

# Component hints: registry skill names appearing whole-word in the task.
comps='[]'
if [ -f "$OPSMAN_REGISTRY_DIR/skills.json" ]; then
  comps=$(jq -r '.[].name' "$OPSMAN_REGISTRY_DIR/skills.json" | while IFS= read -r n; do
    if printf '%s\n' "$task" | grep -qiw -- "$n"; then
      printf '%s\n' "$n"
    fi
  done | jq -Rn '[inputs]')
fi

jq -n --arg goal "$task" --argjson keywords "$kw" --argjson comps "$comps" '
  {goal: $goal, domain: null, keywords: $keywords, risk: null,
   symptoms: [], affected_components: $comps, tools: [], file_patterns: [],
   constraints: [], unknowns: [], acceptance_criteria: [], prohibited_actions: []}
' >"$out.tmp"
mv "$out.tmp" "$out"
log_info "scaffolded $out — analyst fills domain, risk, keywords, acceptance_criteria"

#!/bin/sh
# Lexical skill scoring: registry x problem.yaml -> candidates.json.
# Signals are transparent and reproducible; no embeddings (per master spec).
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/json.sh"

usage() {
  printf 'usage: select-skills.sh --run <run-id> [--force]\n' >&2
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
problem=$run_dir/problem.yaml
[ -f "$problem" ] || die "$EX_ARTIFACT" "problem.yaml missing — the analyst must classify first"
json_valid "$problem" || die "$EX_ARTIFACT" "problem.yaml is not valid JSON"
skills=$OPSMAN_REGISTRY_DIR/skills.json
[ -f "$skills" ] || die "$EX_ARTIFACT" "registry missing — run: opsman map"
scriptsidx=$OPSMAN_REGISTRY_DIR/scripts.json
[ -f "$scriptsidx" ] || scriptsidx=/dev/null

out=$run_dir/candidates.json
if [ -f "$run_dir/selected-skills.yaml" ] && [ "$force" -ne 1 ]; then
  die "$EX_STATE" "selection already recorded (selected-skills.yaml exists); use --force to rescore"
fi

# trigger_match note: the M1 registry carries no opsman.yaml triggers yet,
# so v1 scores keyword hits against the skill-name tokens (spec fallback).
jq -n \
  --slurpfile skills "$skills" \
  --slurpfile problem "$problem" \
  --slurpfile scriptsidx "$scriptsidx" '
  def words: ascii_downcase | [scan("[a-z0-9][a-z0-9_-]*")] | unique;
  def hits($terms; $bag): [$terms[] | select(. as $t | ($bag | index($t)) != null)];
  def ratio($h; $terms): if ($terms | length) > 0 then (($h | length) / ($terms | length)) else 0 end;
  ($problem[0]) as $p
  | ([$p.keywords[]? | ascii_downcase] | unique) as $kw
  | ([($p.affected_components[]?, $p.tools[]?) | ascii_downcase] | unique) as $tools
  | ([$p.file_patterns[]? | words[]] | unique) as $fpat
  | ($scriptsidx[0]) as $sx
  | [ $skills[0][]
      | . as $s
      | ($s.description | words) as $desc
      | ($s.name | words) as $namew
      | ([$sx[]? | select(.skill == $s.name) | (.path | split("/")[-1] | words[])] | unique) as $scr
      | hits($kw; $desc) as $dm
      | hits($kw; $namew) as $tm
      | hits($tools; ($desc + $namew + $scr | unique)) as $om
      | hits($fpat; $desc) as $fm
      | {name: $s.name,
         skill_dir: $s.skill_dir,
         score: (((0.35 * ratio($dm; $kw)) + (0.20 * ratio($tm; $kw))
                  + (0.15 * ratio($om; $tools)) + (0.10 * ratio($fm; $fpat))) * 100 | round / 100),
         signals: {
           description_match: {weight: 0.35, hits: ($dm | length), matched: $dm},
           trigger_match: {weight: 0.20, hits: ($tm | length), matched: $tm},
           tool_match: {weight: 0.15, hits: ($om | length), matched: $om},
           file_match: {weight: 0.10, hits: ($fm | length), matched: $fm},
           historical_success: {weight: 0.10, hits: 0, matched: "not-implemented"},
           dependency_compatibility: {weight: 0.05, hits: 0, matched: "not-implemented"},
           cost_efficiency: {weight: 0.05, hits: 0, matched: "not-implemented"}
         }}
    ]
  | sort_by(-.score, .name)
' >"$out.tmp"
mv "$out.tmp" "$out"
log_info "candidates scored: $out ($(jq 'length' "$out") skills)"

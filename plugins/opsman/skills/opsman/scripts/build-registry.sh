#!/bin/sh
# Builds the deterministic capability registry from discover.sh output.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"

usage() {
  printf 'usage: build-registry.sh [--output <dir>]\n' >&2
}

out=$OPSMAN_REGISTRY_DIR
case "${1:-}" in
  --output)
    out=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    usage
    exit "$EX_USAGE"
    ;;
esac

need_cmd jq
mkdir -p "$out"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

"$SCRIPT_DIR/discover.sh" >"$tmp"

jq -s 'group_by(.name) | map(sort_by(.precedence)[0] | del(.precedence)) | sort_by(.name)' \
  "$tmp" >"$out/skills.json.tmp"
mv "$out/skills.json.tmp" "$out/skills.json"

# index_files <subdir> <name-pattern> <output-file>
index_files() {
  _ix_sub=$1
  _ix_pat=$2
  _ix_out=$3
  jq -c '.[]' "$out/skills.json" | while IFS= read -r entry; do
    _ix_name=$(printf '%s' "$entry" | jq -r '.name')
    _ix_dir=$(printf '%s' "$entry" | jq -r '.skill_dir')
    [ -d "$_ix_dir/$_ix_sub" ] || continue
    find "$_ix_dir/$_ix_sub" -type f -name "$_ix_pat" 2>/dev/null \
      | LC_ALL=C sort \
      | while IFS= read -r f; do
        jq -cn --arg skill "$_ix_name" --arg path "$f" '{skill: $skill, path: $path}'
      done
  done | jq -s 'sort_by(.skill, .path)' >"$_ix_out.tmp"
  mv "$_ix_out.tmp" "$_ix_out"
}

index_files agents '*' "$out/agents.json"
index_files scripts '*.sh' "$out/scripts.json"

{
  printf '# Capability Map\n\n'
  printf 'Skills discovered by opsman, deduplicated by precedence.\n\n'
  jq -r '.[] | "- **\(.name)** — \(.description) (`\(.skill_dir)`)"' "$out/skills.json"
} >"$out/capability-map.md.tmp"
mv "$out/capability-map.md.tmp" "$out/capability-map.md"

{
  for f in skills.json agents.json scripts.json capability-map.md; do
    printf '%s  %s\n' "$(sha256_file "$out/$f")" "$f"
  done
} >"$out/registry.sha256.tmp"
mv "$out/registry.sha256.tmp" "$out/registry.sha256"

log_info "registry built: $out ($(jq 'length' "$out/skills.json") skills)"

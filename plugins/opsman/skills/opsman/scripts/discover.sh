#!/bin/sh
# Emits one JSON object per SKILL.md candidate found in the ordered roots.
# Dedup happens in build-registry.sh (lowest precedence number wins).
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"

need_cmd jq

# fm_field <file> <key> — value of a frontmatter key (v1: single-line values).
fm_field() {
  awk -v key="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    {
      k = $1
      sub(/:$/, "", k)
      if (k == key) {
        sub(/^[^:]*:[[:space:]]*/, "")
        gsub(/^"|"$/, "")
        print
        exit
      }
    }
  ' "$1"
}

roots_file=$(mktemp)
trap 'rm -f "$roots_file"' EXIT
{
  printf '%s\n' "$OPSMAN_ROOT/.claude/skills"
  printf '%s\n' "$OPSMAN_ROOT/.agents/skills"
  printf '%s\n' "$OPSMAN_ROOT/plugins"
  printf '%s\n' "${OPSMAN_CLAUDE_PLUGIN_CACHE:-$HOME/.claude/plugins/cache}"
  printf '%s\n' "$HOME/.agents/skills"
  if [ -n "${OPSMAN_SKILL_PATH:-}" ]; then
    printf '%s\n' "$OPSMAN_SKILL_PATH" | tr ':' '\n'
  fi
} >"$roots_file"

prec=0
while IFS= read -r root; do
  prec=$((prec + 1))
  if [ -z "$root" ] || [ ! -d "$root" ]; then continue; fi
  find "$root" -name .opsman -prune -o -type f -name SKILL.md -print 2>/dev/null \
    | LC_ALL=C sort \
    | while IFS= read -r sk; do
      dir=$(dirname "$sk")
      name=$(fm_field "$sk" name)
      [ -n "$name" ] || name=$(basename "$dir")
      desc=$(fm_field "$sk" description)
      jq -cn \
        --arg name "$name" \
        --arg desc "$desc" \
        --arg dir "$dir" \
        --arg root "$root" \
        --argjson prec "$prec" \
        --arg hash "$(sha256_file "$sk")" \
        '{name: $name, description: $desc, skill_dir: $dir, root: $root, precedence: $prec, sha256: $hash}'
    done
done <"$roots_file"

#!/usr/bin/env bash
set -euo pipefail

# Every plugin that ships both a Claude and a Codex manifest must carry the
# same non-empty version in both — plugin updates only reach users when the
# version changes, and the two manifests are required to be bumped together.

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

errors=0
checked=0

mapfile -t plugins < <(git ls-files | awk -F/ 'NF >= 3 && $1 == "plugins" {print $2}' | sort -u)

read_version() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
version = data.get("version")
print("" if version is None else str(version))
PY
}

for plugin in "${plugins[@]}"; do
  claude_manifest="plugins/$plugin/.claude-plugin/plugin.json"
  codex_manifest="plugins/$plugin/.codex-plugin/plugin.json"
  git ls-files --error-unmatch "$claude_manifest" >/dev/null 2>&1 || continue
  git ls-files --error-unmatch "$codex_manifest" >/dev/null 2>&1 || continue

  claude_version="$(read_version "$claude_manifest")"
  codex_version="$(read_version "$codex_manifest")"
  checked=$((checked + 1))

  if [[ -z "$claude_version" ]]; then
    echo "::error file=$claude_manifest::Plugin '$plugin' manifest is missing a non-empty 'version'"
    errors=$((errors + 1))
  elif [[ "$claude_version" != "$codex_version" ]]; then
    echo "::error file=$codex_manifest::Plugin '$plugin' manifest versions differ (claude=$claude_version codex=$codex_version) — bump both together"
    errors=$((errors + 1))
  fi
done

if ((errors > 0)); then
  echo "Manifest version validation failed with $errors issue(s)."
  exit 1
fi

echo "Manifest version parity passed for $checked plugin(s)."

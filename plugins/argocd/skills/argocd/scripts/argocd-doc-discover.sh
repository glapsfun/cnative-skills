#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: argocd-doc-discover.sh

List official Argo CD documentation, examples, manifests, and chart files from upstream GitHub repositories.
Requires curl and python3.
EOF
  exit 0
fi

repos=(
  "argoproj/argo-cd@master:docs examples manifests"
  "argoproj/argo-helm@main:charts/argo-cd"
)

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for Argo CD documentation discovery" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for JSON filtering" >&2
  exit 1
fi

for item in "${repos[@]}"; do
  repo_ref="${item%%:*}"
  repo="${repo_ref%@*}"
  ref="${repo_ref#*@}"
  prefixes="${item#*:}"

  echo "## ${repo} (${ref})"
  tree_json="$(curl -fsSL "https://api.github.com/repos/${repo}/git/trees/${ref}?recursive=1" 2>/dev/null || true)"
  if [[ -z "${tree_json}" ]]; then
    echo "Unable to fetch repository tree from GitHub"
    echo
    continue
  fi

  printf '%s' "${tree_json}" |
    python3 -c '
import json
import sys

prefixes = sys.argv[1].split()
data = json.load(sys.stdin)
paths = []
for entry in data.get("tree", []):
    path = entry.get("path", "")
    if entry.get("type") != "blob":
        continue
    if not (path.endswith(".md") or path.endswith(".yaml") or path.endswith(".yml")):
        continue
    if any(path == p or path.startswith(p + "/") for p in prefixes):
        paths.append(path)
for path in sorted(paths)[:240]:
    print(path)
' "${prefixes}"
  echo
done

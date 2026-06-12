#!/usr/bin/env bash
set -euo pipefail

repos=(
  "fluxcd/website:content/en/flux"
  "fluxcd/flux2:manifests"
  "fluxcd/source-controller:docs config/crd/bases api/v1"
  "fluxcd/kustomize-controller:docs config/crd/bases api/v1"
  "fluxcd/notification-controller:docs config/crd/bases api/v1 api/v1beta"
  "fluxcd/flux-schema:docs catalog actions"
  "fluxcd/agent-skills:skills"
)

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for Flux documentation discovery" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for JSON filtering" >&2
  exit 1
fi

for item in "${repos[@]}"; do
  repo="${item%%:*}"
  prefixes="${item#*:}"
  echo "## ${repo}"
  curl -fsSL "https://api.github.com/repos/${repo}/git/trees/main?recursive=1" |
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
for path in sorted(paths)[:220]:
    print(path)
' "${prefixes}"
  echo
done

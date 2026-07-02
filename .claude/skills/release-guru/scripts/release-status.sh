#!/usr/bin/env bash
set -euo pipefail

# Read-only release preflight report for this repository:
# last tag, commits since, plugins changed since the tag (with their manifest
# versions), branch/tree state, and CI status of HEAD. Makes no changes and
# never talks to the network except through `gh` (GitHub API, read-only).

cd "$(git rev-parse --show-toplevel)"

last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
head_sha="$(git rev-parse --short HEAD)"
branch="$(git rev-parse --abbrev-ref HEAD)"

echo "Branch: ${branch} @ ${head_sha}"
if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree: DIRTY (blocks release)"
else
  echo "Working tree: clean"
fi

if git rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
  read -r ahead behind < <(git rev-list --left-right --count '@{upstream}...HEAD' | awk '{print $2, $1}')
  echo "Sync with upstream: ${ahead} ahead / ${behind} behind"
else
  echo "Sync with upstream: no upstream configured"
fi

echo
if [ -z "${last_tag}" ]; then
  echo "Last tag: none (first release)"
  range=""
else
  echo "Last tag: ${last_tag} ($(git log -1 --format=%cs "${last_tag}"))"
  range="${last_tag}..HEAD"
fi

echo
echo "Commits since ${last_tag:-repo start}:"
git log ${range:+"${range}"} --oneline --no-decorate | head -50

echo
echo "Plugins changed since ${last_tag:-repo start} (manifest versions must be bumped for these):"
changed="$(git diff --name-only ${range:+"${range}"} -- plugins/ 2>/dev/null | cut -d/ -f2 | sort -u)"
if [ -z "${changed}" ]; then
  echo "  none"
else
  for p in ${changed}; do
    v_claude="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","?"))' "plugins/${p}/.claude-plugin/plugin.json" 2>/dev/null || echo "?")"
    v_codex="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","?"))' "plugins/${p}/.codex-plugin/plugin.json" 2>/dev/null || echo "?")"
    marker=""
    [ "${v_claude}" != "${v_codex}" ] && marker="  <-- MANIFEST VERSIONS DIFFER"
    # A plugin absent at the last tag is shipping for the first time: its
    # initial version is fine as-is, no bump needed.
    if [ -n "${last_tag}" ] && ! git ls-tree -d "${last_tag}" "plugins/${p}" 2>/dev/null | grep -q .; then
      marker="  (NEW since ${last_tag} — ships at initial version, no bump needed)${marker}"
    fi
    echo "  ${p}: claude=${v_claude} codex=${v_codex}${marker}"
  done
fi

echo
if command -v gh >/dev/null 2>&1; then
  echo "CI runs for HEAD:"
  gh run list --commit "$(git rev-parse HEAD)" --limit 3 2>/dev/null || echo "  (gh query failed — check auth/network)"
else
  echo "CI status: gh not installed; check the Actions tab manually"
fi

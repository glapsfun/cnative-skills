#!/usr/bin/env bash
set -euo pipefail

# Verify the sre-agent generated artifacts (Claude agents + Codex TOMLs) are
# in sync with their playbook sources in
# plugins/sre-agent/skills/sre-agent/references/investigators/.
# Regenerates into a temp dir (read-only against the tree) and diffs.

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

bash scripts/gen-sre-agent-artifacts.sh --out "$tmp_dir" >/dev/null

status=0
for rel in \
  "plugins/sre-agent/agents" \
  "plugins/sre-agent/skills/sre-agent/agents/codex"; do
  if ! diff_output="$(diff -ru "$rel" "$tmp_dir/$rel" 2>&1)"; then
    status=1
    echo "::error::$rel is out of sync with references/investigators/ — run scripts/gen-sre-agent-artifacts.sh and commit the result"
    echo "$diff_output"
  fi
done

if [[ "$status" -eq 0 ]]; then
  echo "sre-agent generated artifacts are in sync."
fi
exit "$status"

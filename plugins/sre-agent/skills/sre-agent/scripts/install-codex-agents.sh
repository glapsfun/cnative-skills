#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-codex-agents.sh [--project]

Install the sre-agent investigator subagents (TOML files bundled with this
skill under agents/codex/) into Codex so the orchestrator can dispatch them
in parallel. Without them the skill still works — it executes the same
playbooks inline, sequentially.

  --project   Install into ./.codex/agents/ (current project) instead of
              the user-level ${CODEX_HOME:-$HOME/.codex}/agents/.
  -h, --help  Show this help.

Idempotent: re-running overwrites previously installed copies. Re-run after
updating the skill so the agents stay in sync with the playbooks.
EOF
}

target="${CODEX_HOME:-$HOME/.codex}/agents"
case "${1:-}" in
  --project) target=".codex/agents" ;;
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$script_dir/../agents/codex"

if ! ls "$source_dir"/*.toml >/dev/null 2>&1; then
  echo "error: no TOML agents found in $source_dir" >&2
  exit 1
fi

mkdir -p "$target"
installed=0
for toml in "$source_dir"/*.toml; do
  cp "$toml" "$target/"
  printf 'installed  %s\n' "$target/$(basename "$toml")"
  installed=$((installed + 1))
done

printf '\n%d Codex subagent(s) installed. Restart Codex to load them.\n' "$installed"

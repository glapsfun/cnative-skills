#!/usr/bin/env bash
set -euo pipefail

# Generate the sre-agent derived artifacts from the investigator playbook
# sources in plugins/sre-agent/skills/sre-agent/references/investigators/:
#   - plugins/sre-agent/agents/<claude-file>            (Claude Code subagents)
#   - plugins/sre-agent/skills/sre-agent/agents/codex/  (Codex TOML subagents)
#
# The playbook sources are the single source of truth. Edit them, run this
# script, and commit the regenerated artifacts. CI enforces sync via
# scripts/checks/sre-agent-artifacts.sh.
#
# Usage: scripts/gen-sre-agent-artifacts.sh [--out <dir>]
#   --out <dir>  Write artifacts under <dir> instead of the repo root
#                (same relative paths). Used by the CI check.

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

out_root="$repo_root"
case "${1:-}" in
  --out)
    if [[ -z "${2:-}" ]]; then
      echo "::error::--out requires a directory argument" >&2
      exit 2
    fi
    out_root="$2"
    ;;
  -h | --help)
    sed -n '3,15p' "$0"
    exit 0
    ;;
  "") ;;
  *)
    echo "::error::unknown argument: $1" >&2
    exit 2
    ;;
esac

OUT_ROOT="$out_root" python3 <<'PY'
import json
import os
import sys
from pathlib import Path

SOURCES_DIR = Path("plugins/sre-agent/skills/sre-agent/references/investigators")
MANIFEST = Path("plugins/sre-agent/.claude-plugin/plugin.json")
REQUIRED_KEYS = ("name", "description", "claude-tools", "claude-file")

out_root = Path(os.environ["OUT_ROOT"])
agents_dir = out_root / "plugins/sre-agent/agents"
codex_dir = out_root / "plugins/sre-agent/skills/sre-agent/agents/codex"

errors = []


def parse_source(path):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        errors.append(f"{path.as_posix()}: missing frontmatter opening '---'")
        return None
    meta = {}
    body_start = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            body_start = i + 1
            break
        if ":" in line:
            key, value = line.split(":", 1)
            meta[key.strip()] = value.strip()
    if body_start is None:
        errors.append(f"{path.as_posix()}: missing frontmatter closing '---'")
        return None
    for key in REQUIRED_KEYS:
        if not meta.get(key):
            errors.append(f"{path.as_posix()}: missing frontmatter key '{key}'")
    body = "".join(lines[body_start:]).lstrip("\n")
    if "'''" in body:
        errors.append(
            f"{path.as_posix()}: body contains ''' which breaks TOML generation"
        )
    return meta, body


def toml_escape(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


version = json.loads(MANIFEST.read_text(encoding="utf-8"))["version"]
sources = sorted(SOURCES_DIR.glob("*.md"))
if not sources:
    print(f"::error::no playbook sources found in {SOURCES_DIR.as_posix()}")
    sys.exit(1)

parsed = [(path, parse_source(path)) for path in sources]
if errors:
    for message in errors:
        print(f"::error::{message}")
    sys.exit(1)

agents_dir.mkdir(parents=True, exist_ok=True)
codex_dir.mkdir(parents=True, exist_ok=True)

for path, (meta, body) in parsed:
    source_rel = path.as_posix().removeprefix("plugins/sre-agent/")
    marker = (
        f"<!-- GENERATED from {path.as_posix()} — "
        "edit the source, then run scripts/gen-sre-agent-artifacts.sh -->"
    )

    agent_path = agents_dir / meta["claude-file"]
    agent_path.write_text(
        "---\n"
        f"name: {meta['name']}\n"
        f"description: {meta['description']}\n"
        f"tools: {meta['claude-tools']}\n"
        "---\n\n"
        f"{marker}\n\n"
        f"{body}",
        encoding="utf-8",
    )

    toml_path = codex_dir / f"{meta['name']}.toml"
    toml_path.write_text(
        f"# GENERATED from {source_rel} (sre-agent v{version}) — "
        "edit the source, then run scripts/gen-sre-agent-artifacts.sh\n"
        f'name = "{toml_escape(meta["name"])}"\n'
        f'description = "{toml_escape(meta["description"])}"\n'
        f"developer_instructions = '''\n{body}'''\n",
        encoding="utf-8",
    )

print(f"Generated {len(parsed)} Claude agent(s) and {len(parsed)} Codex TOML(s).")
PY

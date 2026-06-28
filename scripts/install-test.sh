#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/install-test.sh

Smoke-test the install contract: every plugin referenced by either marketplace
catalog must have its source directory and Claude manifest present on disk.
  -h, --help  Show this help.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

cd "$REPO_ROOT"
require_tool python3

python3 <<'PY'
import json
import sys
from pathlib import Path

catalogs = [
    Path(".claude-plugin/marketplace.json"),
    Path(".agents/plugins/marketplace.json"),
]

errors = []
checked = 0

for catalog in catalogs:
    if not catalog.exists():
        errors.append(f"{catalog}: missing marketplace catalog")
        continue
    try:
        data = json.loads(catalog.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{catalog}: invalid JSON: {exc}")
        continue

    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        errors.append(f"{catalog}: 'plugins' must be a non-empty array")
        continue

    for i, entry in enumerate(plugins):
        loc = f"{catalog} (plugins[{i}])"
        raw = entry.get("source") if isinstance(entry, dict) else None
        # Claude catalog: source is a path string. Codex catalog: source is an
        # object like {"path": "./plugins/x", "source": "local"}.
        if isinstance(raw, dict):
            source = raw.get("path")
        else:
            source = raw
        if not isinstance(source, str) or not source.strip():
            errors.append(f"{loc}: missing 'source' path")
            continue
        src_dir = Path(source[2:] if source.startswith("./") else source)
        if not src_dir.is_dir():
            errors.append(f"{loc}: source dir not found: {src_dir.as_posix()}")
            continue
        manifest = src_dir / ".claude-plugin" / "plugin.json"
        if not manifest.exists():
            errors.append(f"{loc}: manifest not found: {manifest.as_posix()}")
            continue
        checked += 1

if errors:
    for e in errors:
        print(f"::error::{e}")
    sys.exit(1)

print(f"Install smoke test passed for {checked} catalog entr(ies).")
PY
log_ok "install smoke test passed"

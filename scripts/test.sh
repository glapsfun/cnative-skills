#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/test.sh

Validate the shape of every tracked evals.json against the skill eval schema.
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
import subprocess
import sys

tracked = subprocess.run(
    ["git", "ls-files"], check=True, capture_output=True, text=True
).stdout.splitlines()

eval_files = sorted(
    p for p in tracked if p.endswith("/evals/evals.json")
)

if not eval_files:
    print("No tracked evals.json files found.")
    sys.exit(0)

errors = []

for path in eval_files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        errors.append(f"{path}: invalid JSON: {exc}")
        continue

    if not isinstance(data.get("skill_name"), str) or not data["skill_name"].strip():
        errors.append(f"{path}: missing non-empty 'skill_name'")

    evals = data.get("evals")
    if not isinstance(evals, list) or not evals:
        errors.append(f"{path}: 'evals' must be a non-empty array")
        continue

    for i, item in enumerate(evals):
        loc = f"{path} (evals[{i}])"
        if not isinstance(item, dict):
            errors.append(f"{loc}: must be an object")
            continue
        # id may be an integer or a string, but must be present and non-empty.
        ident = item.get("id")
        if isinstance(ident, bool) or ident is None or (
            isinstance(ident, str) and not ident.strip()
        ):
            errors.append(f"{loc}: missing non-empty 'id'")
        elif not isinstance(ident, (int, str)):
            errors.append(f"{loc}: 'id' must be an integer or string")
        prompt = item.get("prompt")
        if not isinstance(prompt, str) or not prompt.strip():
            errors.append(f"{loc}: missing non-empty 'prompt'")

if errors:
    for e in errors:
        print(f"::error::{e}")
    sys.exit(1)

print(f"Eval schema validation passed for {len(eval_files)} file(s).")
PY
log_ok "tests passed"

#!/usr/bin/env bash
set -euo pipefail

# cupgrade-memo-init.sh — scaffold docs/upgrades/<plugin>.md from what the
# plugin already contains: manifest name/version/description, the upstream
# repo its version-check script queries, the URLs its skill cites (ranked by
# frequency), any baseline/verified statements, and a file map. The result
# has TODO markers the agent fills before the first research step.
# Read-only except for writing the memo file.

cd "$(git rev-parse --show-toplevel)"

usage() {
  cat <<'USAGE'
Usage: cupgrade-memo-init.sh <plugin> [--force]

Write docs/upgrades/<plugin>.md scaffold. Refuses to overwrite unless --force.
USAGE
}

force=false
plugin=""
while (($# > 0)); do
  case "$1" in
    --force) force=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -n "$plugin" ]]; then
        echo "only one plugin at a time" >&2
        exit 2
      fi
      plugin="$1"
      ;;
  esac
  shift
done

if [[ -z "$plugin" ]]; then
  usage
  exit 2
fi
if [[ ! -f "plugins/$plugin/.claude-plugin/plugin.json" ]]; then
  echo "error: plugins/$plugin/.claude-plugin/plugin.json not found" >&2
  exit 1
fi
memo="docs/upgrades/$plugin.md"
if [[ -f "$memo" && "$force" != true ]]; then
  echo "error: $memo exists (use --force to overwrite)" >&2
  exit 1
fi
mkdir -p docs/upgrades

last_commit="$(git log -1 --format=%cs -- "plugins/$plugin" 2>/dev/null || true)"

CUPGRADE_LAST_COMMIT="$last_commit" python3 - "$plugin" "$memo" <<'PY'
import datetime as dt
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

plugin, memo_path = sys.argv[1], Path(sys.argv[2])
root = Path("plugins") / plugin
skill = root / "skills" / plugin
manifest = json.loads((root / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
today = dt.date.today().isoformat()
last_commit = os.environ.get("CUPGRADE_LAST_COMMIT") or today

text_files = sorted(p for p in skill.rglob("*") if p.suffix in (".md", ".sh", ".yaml", ".yml", ".json") and p.is_file())
corpus = {p: p.read_text(encoding="utf-8", errors="replace") for p in text_files}

# Upstream repo: the default of a REPO="${X:-owner/name}" line in any bundled script.
repo = ""
for p, body in corpus.items():
    if p.suffix != ".sh":
        continue
    m = re.search(r':-([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)\}"', body)
    if m and "api.github.com" in body:
        repo = m.group(1)
        break

# Baseline constant from a version-check script, e.g. BASELINE="${X:-v1.2.3}" or BASELINE_DEFAULT="1.2.3".
baseline_version = ""
for p, body in corpus.items():
    if p.suffix != ".sh":
        continue
    m = re.search(r'BASELINE(?:_DEFAULT|_VERSION)?="(?:\$\{[A-Z_]+:-)?(v?[0-9][0-9A-Za-z.-]*)\}?"', body)
    if m:
        baseline_version = m.group(1)
        break

# Cited URLs, ranked by frequency; placeholders and localhost dropped.
junk = re.compile(
    r"(localhost|127\.0\.0\.1|example\.(com|org|net)|kubernetes\.default|my-?org|myrepo|/org/repo|\.git$|"
    r"\ba\.b\b|discord\.gg|schemastore|api\.github\.com|githubusercontent\.com|releases/latest/download|"
    r"[?]|github\.com/[A-Za-z0-9_.-]+$|your-|private|xxx|contoso|\d+\.\d+\.\d+\.\d+|\.svc\b|"
    r"webhook|slack\.com|accounts\.google|okta|amazonaws\.com|bitnami|source\.developers|my-)"
)
urls = Counter()
for body in corpus.values():
    for u in re.findall(r"https?://[A-Za-z0-9./_%#?=&+-]+", body):
        u = u.rstrip(".,;:)>")
        if not junk.search(u):
            urls[u] += 1
top_urls = [u for u, _ in urls.most_common(15)]

# Baseline / verified statements already in the skill.
baseline_re = re.compile(r"(baseline|verified against|snapshot date|content verified|latest .* release found)", re.I)
baseline_lines = []
for p, body in corpus.items():
    if p.suffix != ".md":
        continue
    for line in body.splitlines():
        if baseline_re.search(line) and "pod-security" not in line and "Baseline Checks" not in line:
            baseline_lines.append(f"{p.relative_to(skill)}: {line.strip()[:160]}")
baseline_lines = baseline_lines[:8]

# Version-like tokens, most frequent first, as hints for the true baseline.
tokens = Counter()
for p, body in corpus.items():
    if p.suffix == ".md":
        tokens.update(re.findall(r"\bv[0-9]+\.[0-9]+(?:\.[0-9]+)?\b", body))
version_hints = ", ".join(f"{t} ({n})" for t, n in tokens.most_common(6)) or "none found"

# File map.
def first_heading(path):
    for line in corpus.get(path, "").splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return "(no heading)"

def script_purpose(path):
    for line in corpus.get(path, "").splitlines()[1:12]:
        s = line.strip()
        if s.startswith("#") and len(s) > 3 and "shellcheck" not in s:
            return s.lstrip("# ").strip()
    return "(no header comment)"

file_map = [f"- `SKILL.md` — {len(corpus.get(skill / 'SKILL.md', '').splitlines())} lines"]
for p in sorted(skill.glob("references/*.md")):
    file_map.append(f"- `references/{p.name}` — {first_heading(p)}")
for p in sorted(skill.glob("scripts/*.sh")):
    file_map.append(f"- `scripts/{p.name}` — {script_purpose(p)}")
evals = skill / "evals" / "evals.json"
if evals.exists():
    try:
        n = len(json.loads(evals.read_text(encoding="utf-8")).get("evals", []))
    except ValueError:
        n = "?"
    file_map.append(f"- `evals/evals.json` — {n} evals")

version_source = "github-release" if repo else "manual"
sources = "\n".join(f"- TODO role: <{u}>" for u in top_urls) or "- TODO: add official docs, releases, changelog URLs"
baseline = "\n".join(f"- {l}" for l in baseline_lines) or "- none stated in the skill"

memo = f"""---
plugin: {plugin}
upstream_name: {manifest.get('displayName') or plugin}
version_source: {version_source}
upstream_repo: {repo}
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: {baseline_version or 'unknown'}
verified_date: {last_commit}
last_upgrade: never
plugin_version: {manifest.get('version', '?')}
check_interval_days: 90
---

# {plugin} — upgrade memo

Scaffolded {today} by cupgrade-memo-init.sh. `verified_date` is the plugin's last content
commit, a proxy until an upgrade run verifies the content against a named upstream version.
Manifest description: {manifest.get('description', '')}

## Sources

TODO: keep official sources, label each (Releases / Changelog / Upgrade guide / Docs / Chart), drop the rest.
{sources}

## Skill map

{chr(10).join(file_map)}

## Watch list

TODO: list every version-sensitive statement and where it lives.
Baseline statements found in the skill:
{baseline}

Version strings seen in the skill (count): {version_hints}

## Open items

- {today}: memo scaffolded; establish `verified_version` on the first update run.

## Upgrade log

(no runs yet)
"""
memo_path.write_text(memo, encoding="utf-8")
print(f"wrote {memo_path} (upstream_repo={repo or 'TODO'}, verified_version={baseline_version or 'unknown'}, {len(top_urls)} source URLs, {len(file_map)} files mapped)")
PY

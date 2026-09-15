#!/usr/bin/env bash
set -euo pipefail

# cupgrade-status.sh — read-only ledger status for the plugins in this repo.
#
# For every tracked plugins/<name>, reads the cupgrade memo frontmatter in
# docs/upgrades/<name>.md, looks up the latest upstream version (unless
# --offline), and prints one row per plugin with a status:
#   NO-MEMO    no memo yet            -> scripts/cupgrade-memo-init.sh <plugin>
#   UNKNOWN    verified_version unknown -> first update run establishes it
#   BEHIND     upstream latest differs from verified_version
#   STALE      verified_date older than check_interval_days (default 90)
#   UNCHECKED  --offline or lookup failed; only staleness is known
#   OK         verified matches latest and is not stale
# A plugin can be BEHIND and past its interval at once; both flags print.
# An age marked "~" comes from a proxy date (verified_proxy: true in the
# memo — last content commit, not a verification).
# --index rewrites the table between the cupgrade-index markers in
# docs/upgrades/README.md from memo data only (no network fields), so the
# tracked file stays stable between runs.
# Network use is read-only GETs to public release APIs.

cd "$(git rev-parse --show-toplevel)"

usage() {
  cat <<'USAGE'
Usage: cupgrade-status.sh [--offline] [--index] [--json] [plugin ...]

  --offline   Do not query upstream; report memo data and staleness only.
  --index     Rewrite the index table in docs/upgrades/README.md (memo data only).
  --json      Print machine-readable rows instead of a table.
  plugin ...  Restrict to these plugins (default: every tracked plugin).

Environment: GH_TOKEN / GITHUB_TOKEN raise the GitHub API rate limit; otherwise
the token from `gh auth token` is used when gh is installed and logged in.
USAGE
}

offline=false
index=false
json=false
plugins=()
while (($# > 0)); do
  case "$1" in
    --offline) offline=true ;;
    --index) index=true ;;
    --json) json=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
    *) plugins+=("$1") ;;
  esac
  shift
done

token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$token" ]] && command -v gh >/dev/null 2>&1; then
  token="$(gh auth token 2>/dev/null || true)"
fi

CUPGRADE_OFFLINE="$offline" CUPGRADE_INDEX="$index" CUPGRADE_JSON="$json" CUPGRADE_TOKEN="$token" \
  python3 - ${plugins[@]+"${plugins[@]}"} <<'PY'
import datetime as dt
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

OFFLINE = os.environ.get("CUPGRADE_OFFLINE") == "true"
INDEX = os.environ.get("CUPGRADE_INDEX") == "true"
JSON = os.environ.get("CUPGRADE_JSON") == "true"
TOKEN = os.environ.get("CUPGRADE_TOKEN", "")
MEMO_DIR = Path("docs/upgrades")
README = MEMO_DIR / "README.md"
TODAY = dt.date.today()
DEFAULT_INTERVAL = 90

tracked = subprocess.run(["git", "ls-files"], check=True, capture_output=True, text=True).stdout.splitlines()
all_plugins = sorted({p.split("/")[1] for p in tracked if p.startswith("plugins/") and p.count("/") >= 2})
wanted = sys.argv[1:] or all_plugins
unknown = [p for p in wanted if p not in all_plugins]
if unknown:
    print(f"error: not a tracked plugin: {', '.join(unknown)}", file=sys.stderr)
    sys.exit(2)


def parse_frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}
    fm = {}
    for line in m.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            fm[key.strip()] = [v.strip().strip("\"'") for v in value[1:-1].split(",") if v.strip()]
        else:
            fm[key.strip()] = value.strip("\"'")
    return fm


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "cnative-skills-cupgrade", "Accept": "application/json"})
    if TOKEN and urllib.parse.urlparse(url).hostname == "api.github.com":
        req.add_header("Authorization", f"Bearer {TOKEN}")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.load(resp)
    except (urllib.error.URLError, urllib.error.HTTPError, ValueError, TimeoutError):
        return None


def latest_upstream(fm):
    """Return (version, published_date, url) or (None, '', hint)."""
    source = fm.get("version_source", "manual")
    repo = fm.get("upstream_repo", "")
    if source == "github-release" and repo:
        data = fetch_json(f"https://api.github.com/repos/{repo}/releases/latest")
        if data:
            return data.get("tag_name"), (data.get("published_at") or "")[:10], data.get("html_url", "")
        return None, "", f"https://github.com/{repo}/releases"
    if source == "github-tag" and repo:
        data = fetch_json(f"https://api.github.com/repos/{repo}/tags?per_page=1")
        if data:
            return data[0].get("name"), "", f"https://github.com/{repo}/tags"
        return None, "", f"https://github.com/{repo}/tags"
    if source == "gitlab-release" and repo:
        enc = urllib.parse.quote(repo, safe="")
        data = fetch_json(f"https://gitlab.com/api/v4/projects/{enc}/releases/permalink/latest")
        if data:
            return data.get("tag_name"), (data.get("released_at") or "")[:10], f"https://gitlab.com/{repo}/-/releases/{data.get('tag_name', '')}"
        return None, "", f"https://gitlab.com/{repo}/-/releases"
    if source == "web-json" and fm.get("upstream_url"):
        data = fetch_json(fm["upstream_url"])
        key = fm.get("upstream_key", "version")
        if isinstance(data, dict) and key in data:
            return str(data[key]), "", fm["upstream_url"]
        return None, "", fm["upstream_url"]
    return None, "", fm.get("upstream_url", "")


def norm(version, match):
    v = (version or "").strip().lstrip("vV")
    if match == "minor":
        parts = v.split(".")
        v = ".".join(parts[:2])
    return v


def read_manifest_version(plugin):
    path = Path("plugins") / plugin / ".claude-plugin" / "plugin.json"
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("version", "?")
    except (OSError, ValueError):
        return "?"


def days_since(iso):
    try:
        return (TODAY - dt.date.fromisoformat(iso)).days
    except (TypeError, ValueError):
        return None


rows = []
for plugin in wanted:
    memo = MEMO_DIR / f"{plugin}.md"
    row = {
        "plugin": plugin,
        "plugin_version": read_manifest_version(plugin),
        "memo": memo.as_posix() if memo.exists() else "",
    }
    if not memo.exists():
        row.update(status="NO-MEMO", verified="", verified_date="", latest="", published="", last_upgrade="", upstream="", url="")
        rows.append(row)
        continue
    fm = parse_frontmatter(memo.read_text(encoding="utf-8"))
    verified = fm.get("verified_version", "unknown")
    vdate = fm.get("verified_date", "")
    interval = int(fm.get("check_interval_days") or DEFAULT_INTERVAL)
    age = days_since(vdate)
    stale = age is not None and age > interval
    match = fm.get("version_match", "exact")
    latest, published, url = (None, "", fm.get("upstream_url", "")) if OFFLINE else latest_upstream(fm)

    if verified in ("", "unknown", "n/a") and fm.get("version_source", "manual") != "manual":
        status = "UNKNOWN"
    elif latest is None:
        status = "UNCHECKED"
    elif norm(latest, match) != norm(verified, match):
        status = "BEHIND"
    else:
        status = "OK"
    if stale and status != "OK":
        status += ",STALE"
    elif stale:
        status = "STALE"
    proxy = fm.get("verified_proxy", "").lower() in ("true", "yes")

    row.update(
        status=status,
        upstream=fm.get("upstream_name", ""),
        verified=verified,
        verified_date=vdate,
        age_days=age,
        proxy=proxy,
        latest=latest or "",
        published=published,
        last_upgrade=fm.get("last_upgrade", ""),
        url=url,
        version_source=fm.get("version_source", "manual"),
    )
    rows.append(row)

order = {"NO-MEMO": 0, "UNKNOWN": 1, "BEHIND": 2, "STALE": 3, "UNCHECKED": 4, "OK": 5}
rows.sort(key=lambda r: (order.get(r["status"].split(",")[0], 9), -(r.get("age_days") or 0), r["plugin"]))

if JSON:
    print(json.dumps(rows, indent=2))
else:
    headers = ["plugin", "plugin ver", "verified", "latest", "published", "age(d)", "status"]
    table = []
    for r in rows:
        age = "" if r.get("age_days") is None else ("~" if r.get("proxy") else "") + str(r["age_days"])
        table.append([r["plugin"], r["plugin_version"], r.get("verified", ""), r.get("latest", ""), r.get("published", ""), age, r["status"]])
    widths = [max(len(h), *(len(row[i]) for row in table)) for i, h in enumerate(headers)]
    fmt = "  ".join("{:<" + str(w) + "}" for w in widths)
    print(fmt.format(*headers))
    print(fmt.format(*("-" * w for w in widths)))
    for row in table:
        print(fmt.format(*row))
    print()
    print("age: days since verified_date; ~ = proxy date (last content commit, never verified)")
    if OFFLINE:
        print("(offline: upstream not queried)")
    for r in rows:
        if r["status"] == "NO-MEMO":
            print(f"{r['plugin']}: no memo — run: bash .claude/skills/cupgrade/scripts/cupgrade-memo-init.sh {r['plugin']}")
        elif r["status"] == "UNCHECKED" and not OFFLINE:
            print(f"{r['plugin']}: could not query upstream ({r.get('version_source')}); check {r.get('url') or 'the memo sources'} manually")
        elif r.get("version_source") == "manual" and r["status"] != "NO-MEMO":
            print(f"{r['plugin']}: manual version source — check {r.get('url') or 'the memo sources'}")

if INDEX:
    if not README.exists():
        print(f"error: {README} not found; cannot write index", file=sys.stderr)
        sys.exit(1)
    text = README.read_text(encoding="utf-8")
    start, end = "<!-- cupgrade-index:start -->", "<!-- cupgrade-index:end -->"
    if start not in text or end not in text:
        print(f"error: {README} lacks the cupgrade-index markers", file=sys.stderr)
        sys.exit(1)
    lines = ["| Plugin | Plugin version | Upstream | Verified against | Verified on | Last upgrade | Memo |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in sorted(rows, key=lambda r: r["plugin"]):
        if r["status"] == "NO-MEMO":
            lines.append(f"| `{r['plugin']}` | {r['plugin_version']} | — | — | — | — | *no memo* |")
        else:
            lines.append(
                f"| `{r['plugin']}` | {r['plugin_version']} | {r['upstream']} | {r['verified']} | {r['verified_date']} | {r['last_upgrade']} | [{r['plugin']}.md]({r['plugin']}.md) |"
            )
    if len(sys.argv) > 1:
        # A partial run must not drop rows for plugins it did not inspect.
        print("error: --index needs the full plugin set; run without plugin arguments", file=sys.stderr)
        sys.exit(2)
    before = text[: text.index(start) + len(start)]
    after = text[text.index(end):]
    README.write_text(before + "\n" + "\n".join(lines) + "\n" + after, encoding="utf-8")
    print(f"index rewritten: {README}")
PY

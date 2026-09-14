#!/usr/bin/env bash
set -euo pipefail

# cupgrade-releases.sh — list upstream releases newer than a given tag, oldest
# first, with dates and URLs; --notes appends each release's notes (trimmed) so
# a research step can see the whole range in one read. GitHub by default,
# GitLab with --gitlab. Read-only: GET requests to public release APIs only.

usage() {
  cat <<'USAGE'
Usage: cupgrade-releases.sh <owner/repo> [--since TAG] [--limit N] [--notes]
                            [--max-chars N] [--prerelease] [--gitlab]

  --since TAG     Releases newer than TAG (by version, so backports of older
                  lines are excluded); with no --since, list the newest N.
  --limit N       Max releases to print (default 40).
  --notes         Print release notes under each entry.
  --max-chars N   Trim each note body to N chars (default 4000).
  --prerelease    Include prereleases/drafts (skipped by default).
  --gitlab        Query gitlab.com instead of GitHub; <owner/repo> is the project path.

Environment: GH_TOKEN / GITHUB_TOKEN raise the GitHub API rate limit; otherwise
the token from `gh auth token` is used when gh is installed and logged in.
USAGE
}

repo=""
since=""
limit=40
notes=false
max_chars=4000
prerelease=false
gitlab=false
while (($# > 0)); do
  case "$1" in
    --since)
      since="${2:-}"
      shift
      ;;
    --limit)
      limit="${2:-}"
      shift
      ;;
    --max-chars)
      max_chars="${2:-}"
      shift
      ;;
    --notes) notes=true ;;
    --prerelease) prerelease=true ;;
    --gitlab) gitlab=true ;;
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
      if [[ -n "$repo" ]]; then
        echo "only one repository at a time" >&2
        exit 2
      fi
      repo="$1"
      ;;
  esac
  shift
done

if [[ -z "$repo" || "$repo" != */* ]]; then
  usage
  exit 2
fi

token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$token" ]] && command -v gh >/dev/null 2>&1; then
  token="$(gh auth token 2>/dev/null || true)"
fi

CUPGRADE_TOKEN="$token" python3 - "$repo" "$since" "$limit" "$notes" "$max_chars" "$prerelease" "$gitlab" <<'PY'
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, since, limit, notes, max_chars, prerelease, gitlab = sys.argv[1:8]
limit, max_chars = int(limit), int(max_chars)
notes, prerelease, gitlab = notes == "true", prerelease == "true", gitlab == "true"
TOKEN = os.environ.get("CUPGRADE_TOKEN", "")


def norm(tag):
    return (tag or "").strip().lstrip("vV")


def vtuple(tag):
    """Numeric tuple for ordering; non-numeric parts sort below numbers."""
    parts = []
    for piece in re.split(r"[.\-+]", norm(tag)):
        parts.append((1, int(piece)) if piece.isdigit() else (0, piece))
    return tuple(parts)


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "cnative-skills-cupgrade", "Accept": "application/json"})
    if TOKEN and not gitlab:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        print(f"error: HTTP {exc.code} for {url}", file=sys.stderr)
        sys.exit(1)
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        print(f"error: {exc} for {url}", file=sys.stderr)
        sys.exit(1)


def page_url(n):
    if gitlab:
        enc = urllib.parse.quote(repo, safe="")
        return f"https://gitlab.com/api/v4/projects/{enc}/releases?per_page=50&page={n}"
    return f"https://api.github.com/repos/{repo}/releases?per_page=50&page={n}"


def normalise(item):
    if gitlab:
        return {
            "tag": item.get("tag_name", ""),
            "date": (item.get("released_at") or "")[:10],
            "url": f"https://gitlab.com/{repo}/-/releases/{item.get('tag_name', '')}",
            "body": item.get("description") or "",
            "pre": bool(item.get("upcoming_release")),
        }
    return {
        "tag": item.get("tag_name", ""),
        "date": (item.get("published_at") or item.get("created_at") or "")[:10],
        "url": item.get("html_url", ""),
        "body": item.get("body") or "",
        "pre": bool(item.get("prerelease") or item.get("draft")),
    }


found_since = since == ""
collected = []
for n in range(1, 9):  # up to 400 releases
    page = get(page_url(n))
    if not page:
        break
    stop = False
    for item in page:
        rel = normalise(item)
        if since and norm(rel["tag"]) == norm(since):
            found_since = True
            stop = True
            break
        if rel["pre"] and not prerelease:
            continue
        if since and vtuple(rel["tag"]) <= vtuple(since):
            continue  # backport patch of an older line, published after --since
        collected.append(rel)
        if not since and len(collected) >= limit:
            stop = True
            break
    if stop or len(page) < 50:
        break

if since and not found_since:
    print(f"warning: --since {since} not found in the first {n * 50} releases of {repo}; listing everything fetched", file=sys.stderr)

collected = collected[:limit]
collected.reverse()  # oldest first, so the range reads chronologically

header = f"{repo}: {len(collected)} release(s)"
if since:
    header += f" after {since}"
if collected:
    header += f" ({collected[0]['date']} … {collected[-1]['date']})"
print(header)
print()
for rel in collected:
    print(f"{rel['tag']}  {rel['date']}  {rel['url']}")
    if notes:
        body = rel["body"].strip()
        if len(body) > max_chars:
            body = body[:max_chars].rstrip() + f"\n… [trimmed to {max_chars} chars; full notes at {rel['url']}]"
        print()
        print(body or "(no release notes)")
        print()
        print("-" * 72)
PY

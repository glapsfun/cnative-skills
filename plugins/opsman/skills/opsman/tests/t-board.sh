#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
. "$(dirname -- "$0")/lib.sh"

command -v python3 >/dev/null 2>&1 || {
  printf 'skip: python3 not available\n'
  exit 0
}

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
run_to_implementing

"$SCRIPTS_DIR/board.sh" --port 0 >"$sandbox/board.out" 2>&1 &
srv=$!
trap 'kill "$srv" 2>/dev/null; rm -rf "$sandbox"' EXIT

url=''
i=0
while [ "$i" -lt 50 ]; do
  url=$(sed -n 's/^opsman board: \(.*\)$/\1/p' "$sandbox/board.out")
  [ -n "$url" ] && break
  sleep 0.2 2>/dev/null || sleep 1
  i=$((i + 1))
done
[ -n "$url" ] || fail "board did not start: $(cat "$sandbox/board.out")"

fetch() { # GET url; prints body; nonzero exit on HTTP error
  python3 -c 'import sys, urllib.request
print(urllib.request.urlopen(sys.argv[1]).read().decode())' "$1"
}
post() { # POST url; nonzero exit on HTTP error
  python3 -c 'import sys, urllib.request
urllib.request.urlopen(sys.argv[1], data=b"x")' "$1"
}

fetch "$url" | grep -q '<title>opsman board</title>' || fail "board html not served"
fetch "${url}api/runs" | jq -e --arg r "$run_id" \
  'any(.[]; .run_id == $r and .status == "IMPLEMENTING")' >/dev/null \
  || fail "/api/runs must list the fixture run"
fetch "${url}runs/$run_id/state.json" | jq -e '.status == "IMPLEMENTING"' >/dev/null \
  || fail "state.json must be served"
fetch "${url}runs/$run_id/events.jsonl" | grep -q '"event":"RunStarted"' \
  || fail "events.jsonl must be served"

# path traversal refused
assert_status 1 fetch "${url}runs/../current"
# files outside the run-file allowlist refused
assert_status 1 fetch "${url}runs/$run_id/plan.yaml.tmp"
# writes refused (GET-only server)
assert_status 1 post "${url}runs/$run_id/state.json"

kill "$srv" 2>/dev/null || true

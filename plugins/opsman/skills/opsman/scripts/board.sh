#!/bin/sh
# Read-only local hub over .opsman/runs for humans watching a run.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/paths.sh"

usage() {
  printf 'usage: board.sh [--port <n>]\n' >&2
}

port=41999
while [ $# -gt 0 ]; do
  case $1 in
    --port)
      [ $# -ge 2 ] || {
        usage
        exit "$EX_USAGE"
      }
      port=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit "$EX_USAGE"
      ;;
  esac
done
case $port in
  '' | *[!0-9]*) die "$EX_USAGE" "port must be a number: $port" ;;
esac

command -v python3 >/dev/null 2>&1 \
  || die "$EX_DEP" "opsman board needs python3 (the kernel itself does not)"
[ -d "$OPSMAN_RUNS_DIR" ] \
  || die "$EX_ARTIFACT" "no runs yet — start one with: opsman start \"<task>\""

html=$SCRIPT_DIR/board/board.html
[ -f "$html" ] || die "$EX_ARTIFACT" "board.html missing: $html"

# Auto-open only for interactive humans (best effort; with --port 0 the
# ephemeral port is unknown here, so the opened URL may miss — the printed
# URL from the server below is authoritative).
if [ -t 1 ]; then
  (
    sleep 1
    if command -v open >/dev/null 2>&1; then
      open "http://127.0.0.1:$port/" >/dev/null 2>&1
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "http://127.0.0.1:$port/" >/dev/null 2>&1
    fi
  ) &
fi

exec python3 - "$OPSMAN_RUNS_DIR" "$html" "$port" <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RUNS = os.path.realpath(sys.argv[1])
HTML = sys.argv[2]
PORT = int(sys.argv[3])

RUN_FILES = {
    "state.json", "events.jsonl", "plan.yaml", "acceptance.yaml",
    "problem.yaml", "selected-skills.yaml", "candidates.json",
    "limits.json", "handoff.md", "STATE.md", "result.md",
}


class Handler(BaseHTTPRequestHandler):
    server_version = "opsman-board"

    def log_message(self, *args):
        pass

    def _send(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            with open(HTML, "rb") as f:
                self._send(200, "text/html; charset=utf-8", f.read())
            return
        if path == "/api/runs":
            runs = []
            for rid in sorted(os.listdir(RUNS)):
                state = os.path.join(RUNS, rid, "state.json")
                if not os.path.isfile(state):
                    continue
                try:
                    with open(state) as f:
                        s = json.load(f)
                except (OSError, ValueError):
                    s = {}
                runs.append({
                    "run_id": rid,
                    "status": s.get("status"),
                    "seq": s.get("seq"),
                    "task": (s.get("task") or {}).get("raw_input"),
                })
            self._send(200, "application/json",
                       json.dumps(runs).encode("utf-8"))
            return
        if path.startswith("/runs/"):
            full = os.path.realpath(os.path.join(RUNS, path[len("/runs/"):]))
            inside = full.startswith(RUNS + os.sep)
            name = os.path.basename(full)
            evidence_meta = "/evidence/" in full and name == "meta.json"
            if not (inside and os.path.isfile(full)
                    and (name in RUN_FILES or evidence_meta)):
                self.send_error(404)
                return
            ctype = ("application/json" if name.endswith(".json")
                     else "text/plain; charset=utf-8")
            with open(full, "rb") as f:
                self._send(200, ctype, f.read())
            return
        self.send_error(404)


server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
print("opsman board: http://127.0.0.1:%d/" % server.server_address[1],
      flush=True)
server.serve_forever()
PY

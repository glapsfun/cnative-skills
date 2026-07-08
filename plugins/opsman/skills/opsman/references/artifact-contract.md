# Opsman Artifact Contract

## Exit codes (all scripts)

| Code | Meaning |
| --- | --- |
| 0 | ok |
| 2 | usage error / unknown verb |
| 3 | invalid state or illegal transition |
| 4 | lock held |
| 5 | schema or artifact invalid |
| 6 | budget exceeded |
| 7 | missing dependency (`jq`, `git`, sha256 tool) |

Errors go to stderr prefixed `opsman:`.

## Control-plane layout (target repo, gitignored)

    .opsman/
      registry/            skills.json agents.json scripts.json
                           capability-map.md registry.sha256
      runs/<run-id>/       state.json STATE.md events.jsonl handoff.md
                           attempts/ evidence/ tests/ reviews/ oracle/ context/
      current              run-id of the active run
      lock/                cooperative lock (mkdir-based; pid file inside)

## Per-run portable files

- `state.json` — authoritative machine state; shallow-validated against
  `schemas/state.schema.json` (required keys present).
- `events.jsonl` — append-only truth. One JSON object per line:
  `{seq, ts, event, from, to, payload}`. `seq` starts at 1 and increases
  by exactly 1. The last event's `to` always equals `state.json .status`.
- `STATE.md` — human-readable mirror, regenerated on every transition.
- `handoff.md` — regenerated on every transition; tells the next agent the
  current state, legal events, and next command.
- `result.md` — terminal states only (milestone 4).

## Writing rules

- Every write is atomic: `<file>.tmp` then `mv`.
- Only `record-event.sh` (via `opsman record`) mutates state, under the
  lock. Scripts never use `eval`.
- Locking is cooperative: `mkdir .opsman/lock`. The pid file records the
  invoking process's parent pid. A held lock is never broken
  automatically; a stale lock (dead pid) is reported for manual release.

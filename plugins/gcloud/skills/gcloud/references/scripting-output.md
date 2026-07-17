# Scripting and Output Control

Rules for gcloud in scripts and CI: never parse default human output (it changes between weekly releases), always request a machine format, filter server-side, disable prompts, and use exit codes — not stderr text — for error handling.

## --format

Syntax: `--format="TYPE..."` where the format type may be followed by attributes in square brackets and a projection in parentheses, e.g. `table[box]` with `(name, status)`. Full reference: `gcloud topic formats`, `gcloud topic projections`.

```bash
gcloud compute instances list --format=json                     # full JSON for jq/python
gcloud compute instances list --format="value(name)"            # bare values, one per line — for shell loops
gcloud compute instances list --format="csv(name,zone,status)"  # headers + rows
gcloud compute instances list --format="table(name, zone.basename(), status)"   # humans
gcloud projects describe my-proj --format="value(projectNumber)"
```

- `value(...)` is the shell-friendly one: no headers, tab-separated fields (add `[separator=","]` after `value` to change the delimiter).
- Projections take **transforms**: `zone.basename()` (strip URL prefix), `timestamp.date()`, `firstof(a,b)`, `join()`, `list()`. Nested fields use dots (`networkInterfaces[0].accessConfigs[0].natIP`).
- `--format=json` + `jq` beats elaborate projections when logic gets complex; `--format="json(name,status)"` narrows JSON to selected keys.
- Table attributes for humans: `table[box,title=VMs]` before the projection, column labels `table(name:label=VM, status:sort=1)`.

## --filter

Server-side filtering; combine with `--format`. Full reference: `gcloud topic filters`.

```bash
--filter="status=RUNNING"
--filter="name~^web-.*"                          # regex
--filter="labels.env=prod AND NOT labels.canary:*"   # label equality + "label not set"
--filter="creationTimestamp<-P30D"               # older than 30 days (ISO8601 duration)
--filter="zone:(us-central1-a us-central1-b)"    # membership
```

Operators: `=` `!=` `<` `<=` `>` `>=`, `:` (has/word match, `*` prefix), `~` (regex), `AND`/`OR`/`NOT` (uppercase; parenthesize when mixing). `key:*` tests existence. Add `--limit` and `--sort-by` where supported.

## Prompts, errors, async

```bash
gcloud compute instances delete web-1 --zone=us-central1-a --quiet   # accept defaults, no prompting
```

- `--quiet`/`-q` (or `core/disable_prompts=1`, or `CLOUDSDK_CORE_DISABLE_PROMPTS=1` in CI) makes commands non-interactive — prompts otherwise hang pipelines. Note `--quiet` accepts the *default* answer, so it confirms deletions: pair it with explicit resource names, never with globs you haven't listed first.
- Exit code `0` = success, non-zero = failure. Branch on that:

  ```bash
  if ! gcloud compute instances describe web-1 --zone="$ZONE" --format=json >/tmp/vm.json 2>/dev/null; then
    echo "instance missing" >&2; exit 1
  fi
  ```

- Do not match on stderr message text — wording changes. `--verbosity=error` quiets progress noise; `--log-http` is the debugging firehose (redacts tokens, still avoid in shared logs).
- Long operations: `--async` returns immediately with an operation ID; wait on it with the product's operations command rather than sleeping. Some groups have a `wait` verb (`gcloud container operations wait`), others only `describe` (`gcloud compute operations describe`, polled until `status=DONE`) — check `gcloud <group> operations --help`.
- Auth for scripts: see `auth.md` — attached SA or workload identity federation in CI, impersonation on workstations; avoid interactive `gcloud init` in any script.

## Idempotency patterns

```bash
# create-if-missing
gcloud pubsub topics describe my-topic >/dev/null 2>&1 \
  || gcloud pubsub topics create my-topic

# capture the one value you need
IP="$(gcloud compute addresses describe lb-ip --region="$REGION" --format='value(address)')"
```

## CLI vs client libraries

Shelling out to gcloud is right for ops automation, CI glue, and one-off scripts. For an *application* making many API calls, use Cloud Client Libraries instead: they authenticate via ADC, reuse connections and tokens (create one client and keep it — per-request clients trigger rate limits and slow auth round-trips), get retries/timeouts built in, and pin cleanly in dependency managers. A shell loop spawning hundreds of `gcloud` processes is the smell that the task outgrew the CLI.

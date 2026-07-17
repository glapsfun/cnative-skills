# Output, --query, Pagination, and Scripting

## Output formats

`--output` flag > `AWS_DEFAULT_OUTPUT` env > profile `output`. Formats: `json` (default), `yaml`, `yaml-stream` (streams large results), `text` (tab-separated, for awk/grep), `table` (humans only), `off` (suppress stdout entirely — check the exit code, errors still hit stderr).

Rules of thumb:

- Scripts consuming structure: `--output json` (+ `jq` for anything JMESPath can't do).
- Scripts consuming columns: `--output text` **always with an explicit `--query` column list** — bare text output orders columns alphabetically by key and shifts between resources/releases. `None` is printed for missing keys.
- Existence checks: `--output off` + exit code (e.g. `aws s3api head-bucket --bucket b --output off 2>/dev/null`).
- **`--query` × output interaction**: with `--output text` the query runs once *per page* (can duplicate "first element" picks across pages); with `json`/`yaml` it runs once over the fully assembled result. Prefer json when the query aggregates.

Pager: v2 pipes everything through `less`/`more` by default and hangs non-interactive jobs. Disable per command with `--no-cli-pager`, per profile with `cli_pager=`, or per environment with `AWS_PAGER=""` — put one of these in every script.

## Server-side vs client-side filtering

Filter server-side first (less data transferred, service does the work), then shape client-side:

- Server-side: service-specific — `--filters Name=...,Values=...` (ec2, rds, autoscaling), `--filter` (ses, ce), `--filter-expression` (dynamodb), `--prefix` (s3api). Check `aws <svc> <cmd> help`.
- Client-side: `--query` (JMESPath) — works on every command, runs after the HTTP response arrives.

```bash
aws ec2 describe-volumes \
  --filters "Name=availability-zone,Values=us-west-2a" "Name=status,Values=attached" \
  --query 'Volumes[?Size > `50`].{Id:VolumeId,Size:Size,Type:VolumeType}'
```

## JMESPath (--query) patterns

| Goal | Expression |
|---|---|
| Project fields per item | `Reservations[*].Instances[*].[InstanceId,State.Name]` |
| Flatten nested lists | `Reservations[].Instances[].InstanceId` (`[]` flattens, `[*]` keeps nesting) |
| Filter items | `Volumes[?State=='available']`; numeric literals go between backticks — see the Size example above |
| Named columns (stable order in table/text) | `Volumes[].{ID:VolumeId,AZ:AvailabilityZone}` |
| First / N-th | `Volumes[0]`, pipe: `Volumes[].VolumeId \| [0]` |
| Slice | `Volumes[:5]`, reverse step `[::-1]` |
| Sort + newest | `reverse(sort_by(Images,&CreationDate))[:5].ImageId` |
| Count | `length(Volumes)` (combine with a filter expression to count matches) |
| Exclude by tag | `Volumes[?!not_null(Tags[?Value=='test'].Value)] \| []` |
| One value per line (text) | `Groups[].[GroupName]` (brackets force rows) |

Quoting: single-quote the whole expression for the shell; JMESPath literals use backticks. Numbers compare only against backtick literals (`` `50` ``). Test expressions interactively with auto-prompt (`aws --cli-auto-prompt`, F5 preview) or `jpterm`.

## Pagination

The CLI auto-paginates by default (follows NextToken/Marker across calls and merges the result).

- `--no-paginate` — single API call, first page only.
- `--page-size N` — smaller per-call batches (fixes timeouts on huge lists); output unchanged.
- `--max-items N` — cap total items; a `NextToken` is emitted when truncated.
- `--starting-token <NextToken>` — resume from a previous truncated run.

Use the same value for `--page-size` and `--max-items` when combining, or ordering anomalies can duplicate/drop items. Note: with `--cli-input-json`, v2 disables auto-pagination when paging params are present (v1 didn't).

## Return codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | One or more S3 transfer operations failed (s3 commands) |
| 2 | Command-dependent (also used by argparse) |
| 130 | Interrupted (SIGINT) |
| 252 | Invalid syntax/parameters — the command never ran |
| 253 | Environment/configuration invalid (missing credentials, bad config) — fix setup, retrying won't help |
| 254 | Service returned an error (permissions, missing resource, throttle) — inspect stderr |
| 255 | General CLI failure |

Script pattern: `set -euo pipefail`, branch on `$?`, treat 252/253 as bugs in the script/environment and 254 as an AWS-side condition. `--debug` dumps the full request/response when diagnosing.

## Robust script checklist

```bash
#!/usr/bin/env bash
set -euo pipefail
export AWS_PAGER=""                      # never hang on a pager
export AWS_RETRY_MODE=standard AWS_MAX_ATTEMPTS=5
PROFILE=ci REGION=eu-central-1           # explicit, never inherited
aws sts get-caller-identity --profile "$PROFILE" --output off   # fail fast on auth
aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,LaunchTime]' --output text
```

Also in the toolbox:

- **Waiters**: `aws <service> wait <condition>` blocks until a state (e.g. `aws ec2 wait instance-running --instance-ids i-…`, `aws cloudformation wait stack-create-complete --stack-name s`). Polls with a timeout; nonzero exit on failure/timeout — always follow a long-running mutation with the matching waiter instead of sleep loops.
- **Dry runs**: EC2 mutations accept `--dry-run` → `DryRunOperation` error means "would have succeeded". Free validation of permissions and parameters.
- **Skeletons/input files**: `aws ec2 run-instances --generate-cli-skeleton input > args.json` (or `yaml-input`), trim, fill, run with `--cli-input-json file://args.json` / `--cli-input-yaml`. Skeleton uses API parameter names (UserName, not --user-name). CLI flags can be combined with the file; flags win. Custom commands (`aws s3` namespace) don't support these.
- **s3 vs s3api**: `aws s3` = high-level (cp/sync/mv/rm/ls/mb/rb/presign, multipart automatic, `--exclude`/`--include`/`--delete`/`--dryrun`); `aws s3api` = raw API (head-object, get-bucket-policy, abort-multipart-upload…). Reach for `s3api` when you need exact API semantics or JSON output; `s3 sync --delete` deletes at the target — always `--dryrun` first.

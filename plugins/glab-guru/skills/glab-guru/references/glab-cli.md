# glab CLI Reference

The GitLab CLI (`glab`) is the preferred way to script against GitLab. It handles auth (including self-managed hosts), endpoint construction, pagination, and output formatting so you never hand-roll `curl` + token headers. Verify flags with `glab <command> --help` — subcommands gain and change flags between weekly releases.

## Setup and auth

```bash
glab auth login                                  # interactive; gitlab.com or custom host, token or OAuth
glab auth login --hostname gitlab.example.com    # self-managed / dedicated instance
glab auth status                                 # who am I, which hosts, token scopes
glab config set editor vim                       # per-host and global config
```

- Credentials are stored per host; `GITLAB_TOKEN` overrides the stored credential (useful in CI), and `GITLAB_HOST` (or `GL_HOST`) selects the instance when outside a git repo.
- Inside a git repo, glab infers host and project from the remote; `-R OWNER/REPO`, `GROUP/SUBGROUP/REPO`, or a full URL targets another project on any authenticated host.
- Tokens need `api` scope for most commands. In CI, prefer a project access token (`glab token create --access-level developer --scope api ...`) over personal tokens; `CI_JOB_TOKEN` works for a limited endpoint set only, so most `glab` calls in pipelines need a real token variable.

## Command map

| Group | Purpose | Everyday examples |
| :--- | :--- | :--- |
| `glab mr` | Merge request lifecycle | `glab mr create --fill --push`, `glab mr view 42`, `glab mr checkout 42`, `glab mr merge --squash --remove-source-branch`, `glab mr approve`, `glab mr rebase`, `glab mr diff` |
| `glab issue` | Issues | `glab issue list --label bug`, `glab issue create`, `glab issue close 12`; `glab work-items` is the newer work-item API |
| `glab ci` | Pipelines (aliases `pipe`/`pipeline` are deprecated) | `glab ci list --status=failed`, `glab ci status --live`, `glab ci view`, `glab ci run -b main`, `glab ci trace <job>`, `glab ci retry`, `glab ci cancel pipeline`, `glab ci lint`, `glab ci config compile` |
| `glab job` | Job artifacts | `glab job artifact main build`, `glab job artifact refs/merge-requests/123/head build --list-paths` |
| `glab release` | Releases | `glab release create v1.2.0 --notes "..."`, `glab release upload v1.2.0 dist/*`, `glab release download` |
| `glab repo` | Projects | `glab repo create org/name --private`, `glab repo clone group/`, `glab repo fork`, `glab repo mirror`, `glab repo members add` |
| `glab variable` | CI/CD variables | `glab variable set KEY value --masked --protected --scope prod`, `glab variable list`, `glab variable export`; `--group` for group-level |
| `glab schedule` | Pipeline schedules | `glab schedule create --cron "0 4 * * *" --ref main --description nightly --variable "MODE:full"` |
| `glab securefile` | Secure files (≤100 files, ≤5 MB, outside the repo) | `glab securefile create cert.p12`, `glab securefile download` |
| `glab token` | Project/group/personal access tokens | `glab token create --access-level developer --scope api name`, `glab token rotate` |
| `glab label` / `glab milestone` / `glab iteration` | Metadata | `glab label create infra --color "#0366d6"` |
| `glab snippet` | Snippets | `glab snippet create -t title file.go` |
| `glab incident` / `glab todo` / `glab user` | Incidents, todos, user events | `glab incident list` |
| `glab cluster` | K8s agents (agentk) | `glab cluster agent bootstrap`, `glab cluster agent update-kubeconfig` |
| `glab runner` / `glab runner-controller` | Runner fleet | `glab runner list`, `glab runner jobs <id>` |
| `glab container-registry` / `glab packages` | Registry and packages | `glab container-registry tag list`, `glab packages download` |
| `glab stack` | Stacked diffs (experimental) | `glab stack create`, `glab stack save`, `glab stack sync` |
| `glab opentofu` | OpenTofu/Terraform state backend | `glab opentofu init`, `glab opentofu state list` |
| `glab duo` | GitLab Duo AI in the terminal | `glab duo ask "revert last commit"` |
| `glab mcp` / `glab skills` | MCP server and Agent Skills for AI agents (experimental) | `glab mcp serve`, `glab skills install` |
| `glab api` | Raw REST/GraphQL | see below |
| `glab alias` / `glab completion` / `glab check-update` | Shell ergonomics | `glab alias set co 'mr checkout'` |

## Structured output: -F json, --jq

List/view commands support `-F/--output json` plus a built-in `--jq` filter (no jq install needed) — always prefer structured output over parsing human-readable text:

```bash
glab mr list -F json --jq '.[] | select(.draft | not) | "\(.iid)\t\(.title)"'
glab ci list -F json --jq '.[] | {id, status, ref}'
glab ci status -F json          # not compatible with --live/--wait/--compact
```

Not every subcommand has `-F json` yet — check `--help`; where it's missing, fall back to `glab api` which always returns JSON.

## glab api: REST and GraphQL

```bash
glab api projects/:fullpath/releases                  # :fullpath auto-filled from cwd (URL-encoded)
glab api projects/:fullpath/pipelines --paginate      # walk all pages
glab api projects/gitlab-org%2Fcli/issues             # explicit project: URL-encode the path
glab api --method POST projects/:fullpath/issues -f title='Bug'
glab api --method DELETE "projects/:fullpath/pipelines/123"
glab api --hostname gitlab.example.com version
glab api projects/:fullpath/jobs --output ndjson      # JSON Lines for large datasets
```

- Placeholders filled from the current repo: `:branch`, `:fullpath`, `:group`, `:id`, `:namespace`, `:repo`, `:user`, `:username`.
- `-f/--raw-field` sends strings; `-F/--field` coerces `true`/`false`/`null`/integers and reads `@file` / `@-` (stdin). Neither parses JSON arrays/objects — use `--input body.json` for a literal JSON body, `--form "file=@./x.png"` for multipart uploads.
- Adding fields implies `POST`; override with `--method`.
- GraphQL: `glab api graphql -f query='...'`; `--paginate` requires an `$endCursor: String` variable and a `pageInfo { hasNextPage endCursor }` selection.

Use `glab api` whenever no purpose-built subcommand exists (protected branches, approval rules, deploy tokens, job token allowlist, project settings). Check the REST docs at `docs.gitlab.com/api/` for the endpoint and send exactly the documented fields.

## MR workflow in practice

```bash
git checkout -b feat/thing && git commit ...
glab mr create --fill --push                 # push branch + open MR from commits
glab mr create --fill --draft --label RFC
glab mr create --related-issue 42 --copy-issue-labels
glab mr checkout 57                          # review someone's MR locally
glab mr approve && glab mr merge --squash --remove-source-branch --when-pipeline-succeeds
```

`glab mr <cmd>` with no argument targets the MR of the current branch. MRs are addressed by IID (per-project number), not global ID.

## In CI (pipeline jobs)

glab is not preinstalled on GitLab runners; use the official image or install it:

```yaml
comment-on-mr:
  image: registry.gitlab.com/gitlab-org/cli:latest
  script:
    - glab mr note "$CI_MERGE_REQUEST_IID" --message "Build passed"
  variables:
    GITLAB_TOKEN: $BOT_TOKEN   # project access token; CI_JOB_TOKEN covers only a few endpoints
```

`GITLAB_HOST` defaults correctly on gitlab.com; set it (or rely on `CI_SERVER_URL` handling in newer releases) on self-managed instances.

# gh CLI Reference

The GitHub CLI (`gh`) is the preferred way to script against GitHub. It handles auth, endpoint construction, pagination, and output formatting so you never hand-roll `curl` + token headers. Verify flags with `gh <command> --help` — subcommands gain and change flags between releases.

## Setup and auth

```bash
gh auth login                 # interactive; choose HTTPS or SSH, browser or token
gh auth status                # who am I, which scopes, which host
gh auth refresh -s <scope>    # add scopes (e.g., read:org, project, workflow)
gh auth token                 # print the token for use by other tools
```

- `gh auth login` stores credentials per host; `GH_TOKEN`/`GITHUB_TOKEN` env vars override the stored credential (useful in CI, where `GH_TOKEN: ${{ github.token }}` lets workflow steps call `gh`).
- Pushing workflow files requires the `workflow` scope on the token.
- Fine-grained PATs and GitHub App tokens work for most commands; a few (notably some GraphQL-backed ones like `gh project`) need classic scopes.

## Command map

| Group | Purpose | Everyday examples |
| :--- | :--- | :--- |
| `gh repo` | Create, clone, fork, view, edit, delete repos | `gh repo create org/name --private --clone`, `gh repo edit --enable-discussions` |
| `gh pr` | Pull request lifecycle | `gh pr create --fill`, `gh pr view --web`, `gh pr checkout 42`, `gh pr merge --squash --delete-branch`, `gh pr checks` |
| `gh issue` | Issues | `gh issue list --label bug --state open`, `gh issue create`, `gh issue develop 12 --checkout` |
| `gh run` | Actions runs | `gh run list --workflow ci.yml`, `gh run view <id> --log-failed`, `gh run watch`, `gh run rerun --failed`, `gh run download` |
| `gh workflow` | Workflow files | `gh workflow list`, `gh workflow view ci.yml`, `gh workflow run deploy.yml -f env=staging`, `gh workflow enable/disable` |
| `gh release` | Releases | `gh release create v1.2.0 --generate-notes`, `gh release upload v1.2.0 dist/*`, `gh release download` |
| `gh secret` / `gh variable` | Actions secrets/variables | `gh secret set NPM_TOKEN`, `gh secret list --env prod`, `gh variable set REGION -b us-east-1` |
| `gh cache` | Actions caches | `gh cache list`, `gh cache delete --all` |
| `gh label` | Labels | `gh label create infra --color 0366d6`, `gh label clone source/repo` |
| `gh ruleset` | Rulesets | `gh ruleset list`, `gh ruleset view <id>`, `gh ruleset check <branch>` |
| `gh project` | Projects (v2) | `gh project list --owner org`, `gh project item-add` (needs `project` scope) |
| `gh search` | Cross-repo search | `gh search prs --review-requested=@me --state=open`, `gh search code 'hashFiles' --owner org` |
| `gh api` | Raw REST/GraphQL | see below |
| `gh extension` | Install/build extensions | `gh extension install owner/gh-name`, `gh extension create` |
| `gh alias` | Custom shortcuts | `gh alias set bugs 'issue list --label=bug'` |
| `gh gist`, `gh codespace`, `gh org`, `gh browse`, `gh status` | Gists, Codespaces, orgs, open-in-browser, notifications | `gh browse -- 'src/main.go:20'` |

## Structured output: --json, --jq, --template

Most list/view commands support structured output — always prefer it over parsing human-readable text:

```bash
gh pr list --json number,title,author,isDraft            # raw JSON
gh pr list --json number,title --jq '.[] | select(.isDraft | not) | "\(.number)\t\(.title)"'
gh pr list --json number,title,updatedAt \
  --template '{{range .}}{{tablerow (printf "#%v" .number) .title (timeago .updatedAt)}}{{end}}'
```

- `--json` with no fields prints the available field names for that command — use this instead of guessing.
- `--jq` runs a jq expression without requiring jq to be installed.
- `--template` uses Go templates with helpers: `tablerow`/`tablerender` (aligned tables), `timeago`, `timefmt`, `autocolor`, `color`, `hyperlink`, `truncate`, `join`, `pluck`, plus Sprig string functions.

## gh api: REST and GraphQL

```bash
gh api repos/{owner}/{repo}/releases/latest               # {owner}/{repo} auto-filled from cwd
gh api repos/{owner}/{repo}/issues -f title='Bug' -f body='...'   # adding fields implies POST
gh api --method PATCH repos/{owner}/{repo} -F delete_branch_on_merge=true
gh api --paginate repos/{owner}/{repo}/issues --jq '.[].title'    # walk all pages
gh api --paginate --slurp ... | jq 'add | length'                 # pages as one array
gh api --method PUT repos/{owner}/{repo}/contents/... --input body.json
```

- `-f` sends raw strings; `-F` coerces types (`true`, `false`, `null`, integers), fills `{owner}`/`{repo}`/`{branch}` placeholders, and reads `@file` / `@-` (stdin).
- `-H "Accept: application/vnd.github+json"` and `-i`/`--verbose` help when debugging; `--cache 1h` caches GET responses.
- GraphQL:

```bash
gh api graphql -f query='
  query($owner: String!, $name: String!, $endCursor: String) {
    repository(owner: $owner, name: $name) {
      pullRequests(first: 100, after: $endCursor, states: OPEN) {
        nodes { number title }
        pageInfo { hasNextPage endCursor }
      }
    }
  }' -F owner='{owner}' -F name='{repo}' --paginate
```

`--paginate` for GraphQL requires the `$endCursor` variable and `pageInfo { hasNextPage endCursor }` selection exactly as shown.

Use `gh api` whenever no purpose-built subcommand exists (e.g., branch protection, deployment statuses, repo topics, traffic stats). Check the REST docs at `docs.github.com/en/rest` for the endpoint and send exactly the documented fields.

## Aliases

```bash
gh alias set bugs 'issue list --label=bug --state=open'
gh alias set --shell stale 'gh pr list --json number,updatedAt --jq ".[] | select(.updatedAt < \"$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d -30days +%Y-%m-%d)\")"'
gh alias list
```

`--shell` aliases run through `sh`, enabling pipes and substitution; plain aliases are argument expansions.

## Extensions

Any repo named `gh-<name>` with a release (or an executable `gh-<name>` script) is an installable extension:

```bash
gh extension search <topic>
gh extension install owner/gh-name
gh extension list / upgrade --all / remove <name>
gh extension create my-tool                # scaffold (script or Go)
gh extension create --precompiled=go my-tool
```

For compiled (Go) extensions: build on [`cli/go-gh`](https://github.com/cli/go-gh) — it exposes the authenticated REST/GraphQL clients, repo context, config, and terminal helpers that `gh` itself uses. Release with the [`cli/gh-extension-precompile`](https://github.com/cli/gh-extension-precompile) action: a `release.yml` triggered on tag push (`v*`) cross-compiles binaries for all supported platforms and attaches them to the release, making the extension installable everywhere. Tags containing `-` publish as prereleases.

## In CI (workflow steps)

`gh` is preinstalled on GitHub-hosted runners. Give it a token and it just works:

```yaml
- name: Comment on PR
  env:
    GH_TOKEN: ${{ github.token }}
  run: gh pr comment "$PR_NUMBER" --body "Build passed"
```

The `GITHUB_TOKEN` only grants what the workflow `permissions` block allows — add `pull-requests: write`, `issues: write`, etc. as needed.

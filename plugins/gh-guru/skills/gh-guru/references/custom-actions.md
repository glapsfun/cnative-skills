# Building Custom Actions

Build a custom action when the same step logic repeats across workflows or repos, or when the user needs behavior no marketplace action covers. Metadata syntax: <https://docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax>.

## Choosing the action type

| Type | Best for | Trade-offs |
| :--- | :--- | :--- |
| **Composite** | Wrapping existing shell/`gh` commands and other actions into one reusable step | No code to bundle; steps run on the host; `shell:` is mandatory on every `run` step |
| **JavaScript/TypeScript** | Logic, API calls, cross-platform behavior, marketplace publishing | Fast startup (no container); must commit bundled `dist/`; Node version fixed by `using:` |
| **Docker** | Fixed toolchains/OS deps, non-JS languages | Linux runners only; image build/pull adds startup latency |

Start composite; graduate to TypeScript when you need real logic or API access. Prefer an action over a reusable workflow when callers should keep control of the job (runner choice, matrix, surrounding steps).

## action.yml anatomy

```yaml
name: "Deploy Preview"
description: "Builds the site and posts a preview link on the PR"
author: "my-org"
branding:
  icon: upload-cloud
  color: blue
inputs:
  environment:
    description: "Target environment"
    required: true
    default: staging
outputs:
  url:
    description: "Preview URL"
    # composite only — JS actions set outputs from code instead:
    value: ${{ steps.deploy.outputs.url }}
runs:
  using: composite
  steps:
    - id: deploy
      shell: bash
      env:
        ENVIRONMENT: ${{ inputs.environment }}
      run: |
        ./scripts/deploy.sh "$ENVIRONMENT"
        echo "url=https://preview.example.com" >> "$GITHUB_OUTPUT"
```

- `name` + `description` are required; `branding` (feather icon + one of the 9 allowed colors) only matters for the Marketplace listing.
- Inputs surface to the code as env vars `INPUT_<UPPERCASED_NAME>`; in JS use `core.getInput('environment')`.
- The action file must sit at the referenced path root: `owner/repo@ref` expects `action.yml` at the repo root; `owner/repo/subdir@ref` supports monorepos of actions.
- Same injection rules as workflows: route `${{ inputs.* }}` and `${{ github.* }}` through `env:` before using them in `run:` scripts — inputs are caller-controlled.

## JavaScript / TypeScript actions

Scaffold from the official templates: [`actions/typescript-action`](https://github.com/actions/typescript-action) (preferred) or [`actions/javascript-action`](https://github.com/actions/javascript-action). Layout:

```
action.yml          # using: node24 (or node20), main: dist/index.js
src/main.ts         # entry point
dist/               # bundled output — MUST be committed
__tests__/
```

```yaml
runs:
  using: node24
  main: dist/index.js
  post: dist/cleanup.js      # optional pre/post hooks, pre-if/post-if conditions
```

Core toolkit packages ([`actions/toolkit`](https://github.com/actions/toolkit)):

- `@actions/core` — `getInput`/`getBooleanInput`, `setOutput`, `exportVariable`, `addPath`, `setSecret` (mask), `summary` (job summary), logging (`info`/`warning`/`error`, `startGroup`), and `setFailed(message)` to fail the step.
- `@actions/github` — `getOctokit(token)` (authenticated Octokit) + `context` (payload, repo, ref, run info).
- `@actions/exec`, `@actions/io`, `@actions/tool-cache` (download/cache tools for setup-style actions), `@actions/cache`, `@actions/artifact`, `@actions/http-client`.

```ts
import * as core from "@actions/core";
import * as github from "@actions/github";

async function run(): Promise<void> {
  try {
    const token = core.getInput("token", { required: true });
    const octokit = github.getOctokit(token);
    const { owner, repo } = github.context.repo;
    const release = await octokit.rest.repos.getLatestRelease({ owner, repo });
    core.setOutput("tag", release.data.tag_name);
  } catch (err) {
    core.setFailed(err instanceof Error ? err.message : String(err));
  }
}
run();
```

**Why `dist/` is committed:** the runner executes `dist/index.js` directly from the repo — there is no install/build step at use time, so the bundle (rollup or `@vercel/ncc`, dependencies included) must be checked in. Keep it honest with the template's `check-dist.yml` workflow, which rebuilds on PRs and fails if the committed `dist/` doesn't match the source. Test locally with `@github/local-action` (stubs the toolkit, reads inputs from a `.env` file). Give the action's own repo the template's CI: unit tests, lint, `check-dist`, CodeQL.

## Docker actions

```yaml
runs:
  using: docker
  image: Dockerfile          # or docker://ghcr.io/org/image:tag (faster: no build)
  args:
    - ${{ inputs.target }}
```

Inputs also arrive as `INPUT_*` env vars. Keep images minimal, non-root where possible, and prefer a prebuilt pinned registry image over `Dockerfile` for startup speed and reproducibility.

## Releasing and versioning

Follow the first-party convention users expect:

1. Tag releases with full semver: `v1.2.3`.
2. Maintain a **moving major tag**: after releasing `v1.2.3`, force-move `v1` to the same commit (`git tag -fa v1 -m "v1.2.3" && git push -f origin v1`). The `typescript-action` template ships `script/release` automating this.
3. Never break compatibility within a major version — breaking input/output/behavior changes mean `v2`.
4. Document in the README which ref style to use; security-conscious consumers will pin your full SHA regardless (and your README example should show `uses: org/action@<sha> # vX.Y.Z`).

What each ref means to consumers: full SHA = immutable (safest); `v1.2.3` tag = stable unless the tag is moved (tags are mutable!); `v1` = opt-in to non-breaking updates; branch = development only. Enable Dependabot (`package-ecosystem: github-actions`) in consuming repos so pinned refs still receive update PRs.

## Publishing to the Marketplace

Requirements: public repo, `action.yml` at the root, unique name, README. Draft a release and tick "Publish this Action to the GitHub Marketplace". `branding` controls the listing tile. Marketplace publishing is optional — `uses: owner/repo@ref` works for any public repo, and private repos can share actions within their org (Settings → Actions → Access).

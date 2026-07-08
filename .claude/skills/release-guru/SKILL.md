---
name: release-guru
description: >-
  Cut, plan, or recover a release of the cnative-skills repository. Use whenever the user
  wants to tag or publish a version, asks "what should the next version be", mentions
  bumping plugin versions, rc/prerelease tags, release notes/changelog, the release
  workflow failing, or deleting/redoing a release — even if they just say "ship it" or
  "let's release".
---

# Release Guru

Releases here are repo-level semver tags: pushing `vX.Y.Z` (or `vX.Y.Z-rc.N`) triggers
`.github/workflows/release.yml`, which runs the full check gate, generates a changelog
with git-cliff (from conventional commits), and publishes a GitHub Release via `gh`.
Authoritative docs: `docs/RELEASING.md`. The steps below exist because each skipped one
has a concrete failure mode — noted inline.

## Step 1 — Gather facts

Run the bundled read-only helper first; it prints the last tag, commits since, plugins
changed since that tag with their manifest versions, tree/branch state, and CI status:

```bash
bash .claude/skills/release-guru/scripts/release-status.sh
```

Preconditions before anything else (each blocks a release):

- On `main`, clean tree, in sync with `origin/main` — the tag must point at a commit that
  is actually on main, or the release ships code nobody reviewed.
- CI green on HEAD (`gh run list --commit "$(git rev-parse HEAD)"`) — the release workflow
  reruns the same gate and will fail the release late instead of early.

## Step 2 — Choose the version

Look at the commits since the last tag and apply the repo's rules:

- New plugin or notable skill content → **MINOR**
- Fixes, typos, docs, CI tweaks → **PATCH**
- Breaking layout or manifest changes → **MAJOR**
- Risky or unsoaked changes → cut `vX.Y.Z-rc.1` first (the workflow auto-marks `-rc.*`
  tags as prereleases)

Present the suggested version with the commit evidence and let the user confirm — the
version is a public promise, not a mechanical output.

## Step 3 — Bump changed plugins' manifests (the most-forgotten step)

Users receive a plugin update **only when its `version` field changes**. A release that
tags new content without bumping the touched plugins ships nothing to anyone.

For every plugin the helper lists as changed since the last tag, bump `version` in BOTH
manifests — they must stay identical:

- `plugins/<name>/.claude-plugin/plugin.json`
- `plugins/<name>/.codex-plugin/plugin.json`

Exception: a plugin that did not exist at the last tag ships for the first time at its
initial version — no bump needed (the helper marks these `NEW`; verify with
`git ls-tree <last-tag> plugins/<name>` if unsure).

Use the same MAJOR/MINOR/PATCH logic per plugin. Commit the bumps (conventional message,
e.g. `chore: bump fluxcd to 1.1.0 for release`) and push before tagging, so the tag
includes them.

## Step 4 — Dry-run the gate

```bash
scripts/release-dryrun.sh vX.Y.Z
```

Refuses on dirty tree, invalid/existing tag; runs `scripts/check.sh --all` (the exact
release gate) and previews the git-cliff changelog. Fix anything it flags before tagging —
a failed Release workflow leaves a tag with no release attached.

## Step 5 — Tag and publish (confirm with the user first)

Tagging and pushing is public and effectively irreversible once seen. Show the user the
final version + changelog preview and get an explicit go-ahead, then:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

Watch and verify:

```bash
gh run list --workflow=release.yml --limit 1
gh run watch <run-id> --exit-status
gh release view vX.Y.Z
```

Done = the Release exists with the expected notes, and `-rc.*` shows as prerelease.

## Recovery

- **Workflow failed mid-run**: the tag exists but no Release does. The workflow is
  idempotent (its only write is `gh release create`) — fix the cause, re-run the failed
  workflow from the Actions tab (`gh run rerun <run-id>`).
- **Bad release, not yet announced**: delete and redo —
  `gh release delete vX.Y.Z --yes && git push --delete origin vX.Y.Z`, fix, re-tag.
- **Already public**: never rewrite a published tag (installs pin against it). Ship the
  fix as the next PATCH and note the regression in its release notes.

## Guardrails

- Never tag from a dirty tree, a non-main branch, or ahead/behind origin.
- Never force-push or move an existing tag.
- Treat the tag push as the point of no return: everything before it is freely redoable,
  so front-load all verification.
- When in doubt between two bump levels, pick the higher one or cut an `-rc.1`.

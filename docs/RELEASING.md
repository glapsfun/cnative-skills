# Releasing

Releases are repo-level semantic-version tags. Pushing a tag `vX.Y.Z`
(or `vX.Y.Z-rc.N` for a prerelease) triggers `.github/workflows/release.yml`,
which runs the full check suite, generates a changelog with git-cliff, and
publishes a GitHub Release.

## Cutting a release

1. Ensure `main` is green and checked out with a clean tree.
2. Dry-run: `scripts/release-dryrun.sh v1.2.0`
   (runs the full gate and previews the changelog).
3. Tag and push:

   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```

4. Watch the Release workflow. On success, a GitHub Release appears.
   `-rc.N` tags are marked as prereleases automatically.

## Versioning

- `vMAJOR.MINOR.PATCH`. Adding a plugin or notable skill content → MINOR.
  Fixes/typos → PATCH. Breaking layout/manifest changes → MAJOR.
- Prereleases: `v1.2.0-rc.1`, `-rc.2`, … before the stable `v1.2.0`.

## Recovery / rollback

- **Bad release, not yet announced:** delete and redo.

  ```bash
  gh release delete v1.2.0 --yes
  git push --delete origin v1.2.0
  # fix, then re-tag
  ```

- **Already public:** never rewrite a published tag. Ship the next patch
  (`v1.2.1`) as the correction and note the regression in its release notes.
- **Workflow failed mid-run:** the tag exists but no Release was created.
  The workflow is idempotent (the only write is `gh release create`), so fix
  the cause and re-run the failed workflow from the Actions tab.

# Reusable CI: include, templates, and CI/CD Components

Order of preference for sharing pipeline config in current GitLab: **CI/CD components** (typed inputs, catalog, semantic versions) → `include:project` pinned to a ref (private reuse) → `include:template` (legacy built-in templates, many being replaced by components) → `include:remote` (last resort; pin with `integrity`).

## include forms

```yaml
include:
  - local: .gitlab/ci/*.yml                  # supports globs
  - project: platform/ci-templates
    ref: v3.2.0                              # always pin: tag or SHA
    file: [/templates/build.yml, /templates/test.yml]
  - template: Jobs/SAST.gitlab-ci.yml        # instance built-ins
  - remote: https://example.com/ci/base.yml
    integrity: sha256-Xa4bJz...              # required practice for remote
  - component: $CI_SERVER_FQDN/platform/components/secret-detection@2.1.0
    inputs:
      stage: test
  - local: extras.yml
    rules:                                    # conditional include
      - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

Includes merge before the main file; same-name jobs in the main file override included ones (hash-merge; arrays replace). Inspect the merged result with `glab ci config compile`.

## Using components

Reference format: `<CI_SERVER_FQDN>/<project-path>/<component-name>@<version>`. Version resolution order: commit SHA → tag → branch → catalog shorthand (`~latest`, `1`, `1.2`). Pin production pipelines to a SHA or exact semver tag; `~latest` is for trying things out. Browse the CI/CD Catalog at `https://gitlab.com/explore/catalog` (or the instance's own catalog).

Inputs are typed and compile-time — they can parameterize things variables can't (stage names, rules blocks):

```yaml
include:
  - component: $CI_SERVER_FQDN/components/docker-build/docker-build@1.4.0
    inputs:
      image-name: $CI_REGISTRY_IMAGE
      platforms: [linux/amd64, linux/arm64]   # array input
```

## Writing a component

Project layout: `README.md` at the root plus a top-level `templates/` directory. Each component is either a single file `templates/<name>.yml` or a directory `templates/<name>/template.yml`.

```yaml
# templates/build/template.yml
spec:
  description: Build and push a container image.
  inputs:
    stage:
      default: build
    image-name:
      type: string
    scan:
      type: boolean
      default: false
    platforms:
      type: array
      default: [linux/amd64]
---
"$[[ inputs.image-name ]]-build":
  stage: $[[ inputs.stage ]]
  script:
    - build.sh --name "$[[ inputs.image-name ]]" --platforms "$[[ inputs.platforms ]]"
```

Authoring rules that keep components composable:

- No global keywords (`default`, top-level `variables` that leak, `workflow`) inside a component — they'd clobber the consumer's pipeline.
- Replace every hardcoded value a consumer might disagree with (stage, image, flags) with an input with a sane default.
- Use `$CI_SERVER_FQDN` / `$CI_API_V4_URL` instead of hardcoding `gitlab.com` so the component works on self-managed instances.
- Input validation: `options: [a, b]`, `regex:`, `type:` (`string`/`number`/`boolean`/`array`), and `spec:inputs:rules` for conditional defaults on newer instances.
- Test the component in its own project's `.gitlab-ci.yml` (include it with `$CI_COMMIT_SHA` as the version) before releasing.

## Publishing to the catalog

1. Project settings → toggle **CI/CD Catalog project** (needs a project description and root `README.md`).
2. Release with semantic version tags via a pipeline job:

```yaml
create-release:
  stage: release
  image: registry.gitlab.com/gitlab-org/cli:latest
  rules: [{if: $CI_COMMIT_TAG =~ /^\d+\.\d+\.\d+$/}]
  script: ['echo "Releasing $CI_COMMIT_TAG"']
  release:
    tag_name: $CI_COMMIT_TAG
    description: "Release $CI_COMMIT_TAG"
```

`glab repo publish catalog` exists for manual publication; the release-keyword pipeline is the normal path. Consumers then resolve `@1`, `@1.2`, `@~latest` shorthands against your releases.

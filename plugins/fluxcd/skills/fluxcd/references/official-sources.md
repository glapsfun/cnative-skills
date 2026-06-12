# Official Sources

Baseline collected: 2026-06-12. Latest `fluxcd/flux2` release found by GitHub API: `v2.8.8`, published 2026-05-20. Always rerun `scripts/fluxcd-version-check.sh` before version-sensitive guidance.

## Core

- Flux docs: https://fluxcd.io/flux/
- Flux source: https://github.com/fluxcd/flux2
- Flux README: https://github.com/fluxcd/flux2/blob/main/README.md
- Flux releases: https://github.com/fluxcd/flux2/releases
- Flux install manifests: https://github.com/fluxcd/flux2/tree/main/manifests
- Flux docs in repo: https://github.com/fluxcd/flux2/tree/main/docs
- Website source tree: https://github.com/fluxcd/website/tree/main/content/en/flux

## Component Docs

- Source controller: https://github.com/fluxcd/source-controller and https://fluxcd.io/flux/components/source/
- Kustomize controller: https://github.com/fluxcd/kustomize-controller and https://fluxcd.io/flux/components/kustomize/
- Helm controller: https://fluxcd.io/flux/components/helm/
- Notification controller: https://github.com/fluxcd/notification-controller and https://fluxcd.io/flux/components/notification/
- Image automation controllers: https://fluxcd.io/flux/components/image/

## Schemas and Agent Skills

- Flux Schema: https://github.com/fluxcd/flux-schema
- Manifest validation guide: https://github.com/fluxcd/flux-schema/blob/main/docs/guides/manifests-validation.md
- Repository discovery guide: https://github.com/fluxcd/flux-schema/blob/main/docs/guides/repo-discovery.md
- Official Flux agent skills: https://github.com/fluxcd/agent-skills
- Official skills discovered: `gitops-knowledge`, `gitops-repo-audit`, `gitops-cluster-debug`
- Local reference index: `references/doc-index.md`
- Refresh command: `bash scripts/fluxcd-doc-discover.sh`

## Useful Discovery Commands

```bash
curl -s 'https://api.github.com/repos/fluxcd/flux2/releases/latest'
curl -s 'https://api.github.com/repos/fluxcd/flux2/contents/manifests?ref=main'
curl -s 'https://api.github.com/repos/fluxcd/website/contents/content/en/flux?ref=main'
curl -s 'https://api.github.com/repos/fluxcd/agent-skills/contents/skills?ref=main'
```

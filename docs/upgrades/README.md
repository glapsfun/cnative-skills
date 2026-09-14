# Upgrade ledger

One memo per plugin records which upstream version its skill content was verified against,
where upstream truth lives (releases, changelogs, docs), what goes stale, and what every
upgrade run changed. The `cupgrade` skill in `.claude/skills/cupgrade/` reads these before
touching a plugin and writes them back afterwards; humans can do the same.

- Memo format: [.claude/skills/cupgrade/references/memo-format.md](../../.claude/skills/cupgrade/references/memo-format.md)
- Status against upstream: `bash .claude/skills/cupgrade/scripts/cupgrade-status.sh`
- Regenerate the index below: `bash .claude/skills/cupgrade/scripts/cupgrade-status.sh --offline --index`

`verified_version: unknown` means the plugin predates the ledger; the first upgrade run
establishes the real baseline. A `verified_date` marked as a proxy in the memo body is the
plugin's last content commit, not a verification.

## Index

<!-- cupgrade-index:start -->
| Plugin | Plugin version | Upstream | Verified against | Verified on | Last upgrade | Memo |
| --- | --- | --- | --- | --- | --- | --- |
| `agentgateway` | 1.0.0 | agentgateway | v1.3.1 | 2026-07-15 | never | [agentgateway.md](agentgateway.md) |
| `argocd` | 1.0.0 | Argo CD | unknown | 2026-06-28 | never | [argocd.md](argocd.md) |
| `aws` | 1.0.0 | AWS CLI v2 | 2.36.1 | 2026-07-17 | never | [aws.md](aws.md) |
| `bash-scripting` | 1.0.0 | GNU Bash + shell toolchain | unknown | 2026-06-28 | never | [bash-scripting.md](bash-scripting.md) |
| `fluxcd` | 1.0.1 | Flux CD | v2.8.8 | 2026-06-12 | never | [fluxcd.md](fluxcd.md) |
| `gcloud` | 1.0.0 | Google Cloud CLI | 576.0.0 | 2026-07-17 | never | [gcloud.md](gcloud.md) |
| `gh-guru` | 1.1.0 | GitHub CLI | v2.96.0 | 2026-07-17 | never | [gh-guru.md](gh-guru.md) |
| `glab-guru` | 1.0.0 | GitLab CLI | v1.108.0 | 2026-07-17 | never | [glab-guru.md](glab-guru.md) |
| `helm` | 1.0.0 | Helm | unknown | 2026-06-28 | never | [helm.md](helm.md) |
| `kagent` | 1.0.0 | kagent | unknown | 2026-06-28 | never | [kagent.md](kagent.md) |
| `karpenter` | 1.0.0 | Karpenter | v1.13.0 | 2026-07-02 | never | [karpenter.md](karpenter.md) |
| `kgateway` | 1.0.0 | kgateway | v2.3.3 | 2026-06-28 | never | [kgateway.md](kgateway.md) |
| `kubernetes-operator` | 1.0.1 | Kubernetes | v1.36.0 | 2026-06-12 | never | [kubernetes-operator.md](kubernetes-operator.md) |
| `prompt-enhancer` | 1.0.0 | Anthropic prompt-engineering docs | n/a | 2026-06-29 | never | [prompt-enhancer.md](prompt-enhancer.md) |
<!-- cupgrade-index:end -->

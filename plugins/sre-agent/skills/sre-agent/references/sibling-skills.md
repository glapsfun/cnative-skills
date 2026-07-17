# Sibling-Skill Deference

Single source of truth for when sre-agent should defer to a sibling
cloud-native skill instead of hand-rolling the same evidence or remediation
step. Check each row's skill against the available-skills list before using
it; if it isn't installed, fall back to the raw command already in the
relevant investigator or remediation playbook — behavior never regresses
when a sibling skill is absent, it only sharpens when one is present.

| Situation | Skill | Use | Fallback |
| :--- | :--- | :--- | :--- |
| Second-tier k8s evidence: NetworkPolicy, DNS, storage/CSI, RBAC | `kubernetes-operator` | `references/networking-storage.md`, `references/security.md` | This skill's own `references/k8s-deep-evidence.md` |
| Sanity-checking a proposed manifest edit before presenting it as a remediation option | `kubernetes-operator` | `scripts/k8s-manifest-lint.sh`, `scripts/k8s-rbac-check.sh` | Manual review of the diff |
| Helm-managed rollback or config-fix evidence (release status, history, computed values, manifest, hooks) | `helm` | `scripts/helm-release-debug.sh` | `helm history <release> -n <ns>` / `helm get values` |
| Chart-authoring questions while writing a Helm-targeted config fix | `helm` | `references/01-chart-anatomy-and-authoring.md` | Proceed with general Helm knowledge |
| Flux sync/drift evidence and verifying a fix landed | `fluxcd` | `references/troubleshooting.md` | `flux get kustomizations -A` / `flux get helmreleases -A` |
| Flux CLI syntax that may have changed between versions | `fluxcd` | `scripts/fluxcd-version-check.sh` | Proceed with general Flux knowledge, note staleness risk |
| Argo CD sync/health evidence and verifying a fix landed | `argocd` | `scripts/argocd-diagnostics.sh` | `argocd app get <app>` / `argocd app history <app>` |
| RBAC/SSO-adjacent incident on an Argo CD-managed resource | `argocd` | `references/04-security-rbac-sso.md` | Proceed with general Argo CD knowledge |
| A remediation option's Steps section writes or edits a script | `bash-scripting` | Apply `references/02-defensive-patterns.md`, then run `scripts/bash-lint.sh` on the script before presenting the option | Manual review against strict-mode basics (`set -euo pipefail`, quote all expansions) |
| EKS node-provisioning issue and Karpenter-managed nodes are detected | `karpenter` | Defer to the skill for NodePool/EC2NodeClass-level debugging | `investigators/eks.md`'s own node-group coverage |
| Deep GitHub platform work while investigating or planning a remediation: gh CLI flags/`--json` details, debugging a GitHub Actions workflow implicated in the incident, Actions security review of a proposed workflow fix | `gh-guru` | `references/gh-cli.md`, `references/workflow-authoring.md` | This skill's own `references/github-investigation.md` raw-fallback commands + general knowledge |
| The same for GitLab-hosted repos: glab CLI details, debugging `.gitlab-ci.yml` pipelines implicated in the incident | `glab-guru` | `references/glab-cli.md`, `references/troubleshooting.md` | Inline `glab` hints in `investigators/changes.md` + general knowledge |
| Deep gcloud CLI work while investigating a GCP/GKE incident: command/flag lookup after a `GAP: query failed` from flag drift, `--format`/`--filter` projection syntax, auth/config troubleshooting | `gcloud` | `references/command-map.md`, `references/scripting-output.md`, `references/auth.md` | This skill's own `references/gcloud-investigation.md` raw-fallback commands + general knowledge |

Karpenter is carried over here from `SKILL.md`'s prior "Reuse installed
skills" paragraph — it isn't one of the five skills this file was written
for (`kubernetes-operator`, `helm`, `fluxcd`, `argocd`, `bash-scripting`),
but this is now the single place sre-agent records sibling-skill deference,
so it doesn't get a second home. The `gh-guru` and `glab-guru` rows were
added later with the GitHub discovery feature, and the `gcloud` row with the
Google Cloud discovery feature — same rule, same single home.

sre-agent's own shipped scripts (`sre-env-discovery.sh`,
`sre-obs-discovery.sh`, `sre-evidence.sh`, `install-codex-agents.sh`) are
already covered by `bash-scripting`'s standard: `scripts/check.sh` (the
suite CI runs on every push/PR) runs `shellcheck` and `shfmt --check`
against every git-tracked `.sh` file repo-wide, including these — no
separate hardening step is needed for them.

---
plugin: fluxcd
upstream_name: Flux CD
version_source: github-release
upstream_repo: fluxcd/flux2
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: v2.9.5
verified_date: 2026-09-28
last_upgrade: 2026-09-28
plugin_version: 1.1.0
check_interval_days: 90
---

# fluxcd — upgrade memo

Ledger entry created 2026-09-14; first verification run 2026-09-28 (v2.8.8 → v2.9.5). `fluxcd/flux2` has no `CHANGELOG.md`; the per-release notes plus each component's `CHANGELOG.md` (linked from the release) are the changelog.

## Sources

- Releases: <https://github.com/fluxcd/flux2/releases> (component versions per release: `manifests/bases/<component>/kustomization.yaml` at the tag)
- Supported releases: <https://fluxcd.io/flux/releases/>
- Upgrade procedure / API migration: <https://github.com/fluxcd/flux2/discussions/5572>, local `flux migrate --help`
- Docs: <https://fluxcd.io/flux/>
- Upgrade guide: <https://fluxcd.io/flux/installation/upgrade/>
- Component API references: <https://fluxcd.io/flux/components/>; spec docs and CRDs at the component tag: `fluxcd/<controller>@<tag> docs/spec/<version>/*.md`, `config/crd/bases/*.yaml` (served versions come from the CRDs)
- Component changelogs: `https://github.com/fluxcd/<controller>/blob/<tag>/CHANGELOG.md` (source, kustomize, helm, notification, image-reflector, image-automation controllers, source-watcher)
- Feature gates: <https://fluxcd.io/flux/components/kustomize/options/>, helm-controller options page; defaults in `internal/features/features.go` at the tag
- Flux CLI plugins: <https://fluxcd.io/flux/cmd/flux_plugin/>; Flux Schema: <https://github.com/fluxcd/flux-schema>, <https://fluxcd.io/flux/cli-plugins/flux-schema/>
- Security: <https://fluxcd.io/flux/security/>, advisories <https://github.com/fluxcd/flux2/security/advisories> and each controller's advisories
- Local binary `flux <cmd> --help` at the verified version (acceptable for flag names)
- Official agent skills: <https://github.com/fluxcd/agent-skills>, <https://fluxcd.io/flux/agent-skills/>
- Leads only: <https://fluxcd.io/blog/>

## Skill map

- `SKILL.md`: 47 lines; routing (incl. "Upgrade Flux or skip minors"), untrusted-content rules, operating rules
- `references/official-sources.md`: baseline line, supported versions, core/component/schema/agent-skill links
- `references/workflows.md`: install/bootstrap, "Upgrading Flux" (apiVersion table, `flux migrate` order, support matrix), repo structure, authoring, validation (`flux schema` plugin, `--strict-substitute`), reconcile
- `references/security-validation.md`: advisories (GHSA-mwcp-qpcg-fr7c), SOPS (Vault/OpenBao k8s auth), RBAC/tenancy, supply chain (SSH commit verification, Sigstore trusted root), network (allow-webhooks, `generic-oidc` Receivers), policy/CI
- `references/troubleshooting.md`: triage, commands (`kubectl get fluxcd -A`), failure classes (Helm v4 defaults, `.spec.ignore`), "After Upgrading to 2.9", evidence bundle
- `references/doc-index.md`: website sections, controller spec/CRD paths for all 7 controllers, flux-schema docs, agent skills
- `scripts/fluxcd-doc-discover.sh`: lists docs + CRD paths from 11 official fluxcd repos via api.github.com (read-only, sanitized)
- `scripts/fluxcd-version-check.sh`: latest `fluxcd/flux2` release vs `BASELINE`, local CLI, cluster controller images
- `evals/evals.json`: 4 evals (created 2026-09-28)

## Watch list

- `references/official-sources.md`: "Baseline collected: 2026-09-28 … v2.9.5", supported minors (2.9/2.8/2.7) and Kubernetes range (1.34–1.36 for 2.9).
- `scripts/fluxcd-version-check.sh`: `BASELINE` default (`v2.9.5`).
- `references/workflows.md` "Upgrading Flux": apiVersion table (Alert/Provider still `v1beta3`; watch for a `notification.toolkit.fluxcd.io/v1` Alert/Provider), `flux migrate` steps, minimum patch (v2.9.5), Flux Operator version for in-cluster migration (v0.53.0+).
- `references/troubleshooting.md` "After Upgrading to 2.9": feature-gate defaults (`StrictPostBuildSubstitutions`, `UseHelm3Defaults`, `postRenderStrategy`); rename the section when the next minor changes defaults.
- `references/security-validation.md`: advisory list (GHSA-mwcp-qpcg-fr7c, go-git version, CVE-2026-47680).
- `references/workflows.md` / `security-validation.md`: `flux schema` plugin commands and plugin dir `~/.fluxcd/plugins`.
- `scripts/fluxcd-doc-discover.sh` repo list; `references/doc-index.md` spec paths (`docs/spec/<version>/`).
- helm-controller Helm SDK version (Helm v4 since Flux 2.8 / helm-controller v1.5.0; upstream `helm.sh/helm/v4` v4.2.4 at v1.6.4); keep consistent with the `helm` plugin.

## Open items

- 2026-09-28: kustomize-controller v1.9.5 Kustomization spec still says undefined `${var}` are substituted with an empty string, contradicting `StrictPostBuildSubstitutions=true` (feature-gate docs and `internal/features/features.go`). The skill follows the feature gate; re-check the spec text.
- 2026-09-28: fluxcd.io installation page lists Kubernetes 1.33–1.35 while the v2.9.0 release notes list 1.34–1.36; the skill follows the release notes.
- 2026-09-28: plugin directory: the 2.9 blog says `~/fluxcd/plugins`, source (`internal/plugin/discovery.go`) and RFC-0013 say `~/.fluxcd/plugins`; skill uses the source.
- 2026-09-28: GHSA-mwcp-qpcg-fr7c has no CVE id; the advisory lists vulnerable `< v2.9.3`, patched `v2.9.4` (v2.9.3 treated as vulnerable).
- 2026-09-28: `trustedRootSecretRef` on HelmChart `.spec.verify` (shared Go type) is unverified; skill documents it for OCIRepository only.
- 2026-09-28: Age post-quantum SOPS support has no official how-to (changelog and blog only); not taught.
- 2026-09-28: the SKILL.md "Upgrade Flux" route and the "After Upgrading to 2.9" section are version-named; generalise or rename on the next minor.
- 2026-09-28: no eval covers the security-validation additions (SSH verify, trusted root, Vault/OpenBao auth, `generic-oidc`); add one if that section grows.

## Upgrade log

### 2026-09-28: v2.8.8 → v2.9.5 (plugin 1.0.1 → 1.1.0)

First run. Range: 6 releases (v2.9.0 2026-06-30, v2.9.1, v2.9.2, v2.9.3, v2.9.4, v2.9.5 2026-08-31); no 2.8.x patch after v2.8.8. Components at v2.9.5: source-controller v1.9.5, kustomize-controller v1.9.5, helm-controller v1.6.4, notification-controller v1.9.4, image-reflector-controller v1.2.5, image-automation-controller v1.2.5, source-watcher v2.2.4.

**Sources consulted**

- <https://github.com/fluxcd/flux2/releases>: notes v2.9.0 … v2.9.5 (via `cupgrade-releases.sh fluxcd/flux2 --since v2.8.8 --notes`)
- <https://github.com/fluxcd/flux2/discussions/5572>: API migration procedure, Flux Operator v0.53.0+
- <https://fluxcd.io/flux/releases/>: supported Flux minors
- <https://fluxcd.io/flux/components/kustomize/options/>, `fluxcd/kustomize-controller@v1.8.5` / `@v1.9.5` `internal/features/features.go`: `StrictPostBuildSubstitutions` default false → true (read directly)
- `fluxcd/kustomize-controller@v1.9.5` `docs/spec/v1/kustomizations.md` + CRD: `.spec.ignore`, `substituteStrategy` enum (read directly), OpenBao/Vault Kubernetes auth
- <https://fluxcd.io/flux/components/helm/helmreleases/#post-render-strategy>, `fluxcd/helm-controller@v1.6.4` CRD: `postRenderStrategy` default `combined`, `waitStrategy` enum (read directly); `CHANGELOG.md` 1.5.0 (Helm v4, SSA default) and 1.6.4
- CRDs at `notification-controller@v1.9.4`, `image-reflector-controller@v1.2.5`, `helm-controller@v1.6.4`: served versions (read directly)
- <https://github.com/fluxcd/flux2/security/advisories/GHSA-mwcp-qpcg-fr7c> (gh API) and `fluxcd/flux2@v2.8.8` / `@v2.9.5` `manifests/policies/allow-webhooks.yaml`: port 9292 restriction (read directly)
- <https://github.com/fluxcd/source-controller/security/advisories/GHSA-jjrm-hr5f-673x> (gh API): CVE-2026-47680, patched source-controller 1.8.5 (= Flux v2.8.8)
- `fluxcd/notification-controller@v1.9.4` `docs/spec/v1/receivers.md`: GCR Secret `email`/`audience`, `generic-oidc`
- `fluxcd/source-controller@v1.9.5` `docs/spec/v1/gitrepositories.md`, `ocirepositories.md`; `fluxcd/image-automation-controller@v1.2.5` `docs/spec/v1/imageupdateautomations.md` and `CHANGELOG.md` 1.2.4: SSH verification/signing, `trustedRootSecretRef`, refspec tightening
- `fluxcd/kustomize-controller@v1.9.5` / `helm-controller@v1.6.4` `CHANGELOG.md`: kubeconfig Secret hardening (2.9.5)
- <https://github.com/fluxcd/flux-schema/blob/main/README.md>, <https://fluxcd.io/flux/cli-plugins/flux-schema/>, <https://fluxcd.io/flux/cmd/flux_plugin/>, `fluxcd/flux2@v2.9.5` `internal/plugin/discovery.go`: schema plugin, `~/.fluxcd/plugins` (read directly); old `docs/guides/*.md` and `docs/config/README.md` return 404
- <https://fluxcd.io/flux/agent-skills/>: official agent skills page
- Local `flux` v2.9.5: `events`, `plugin`, `plugin install`, `migrate`, `diff kustomization`, `install`, `bootstrap`, `create secret receiver` help (workspace `flux-local-help.txt`)
- <https://fluxcd.io/blog/>: "Announcing Flux 2.9 GA" (lead only; features confirmed above)

**Applied**

- `SKILL.md`: description triggers on API migrations / `flux schema`; "Author or review manifests" points at the apiVersion table and `flux schema validate`; new "Upgrade Flux or skip minors" route; troubleshooting route mentions "After Upgrading to 2.9"
- `references/official-sources.md`: baseline v2.9.5 (collected 2026-09-28), supported minors and Kubernetes range; supported-releases and #5572 links; helm/image/source-watcher repos; flux-schema as the `schema` plugin with fixed doc links; agent-skills page
- `references/workflows.md`: new "Upgrading Flux" (apiVersion table, removed `v1beta2` APIs, `flux migrate` order with the cluster-mode caution, Flux Operator v0.53.0+, minimum v2.9.5, Kubernetes 1.34–1.36 vs `flux check --pre`, supported minors, CLI/controller skew); Validation now `flux plugin install schema` + `flux schema validate|discover`, plugin dir and CI pinning, `--strict-substitute`
- `references/troubleshooting.md`: `kubectl get fluxcd -A`; Helm v4 defaults since 2.8 in "Helm failure"; `.spec.ignore` in "Prune/drift surprise"; new "After Upgrading to 2.9" table (strict substitution, `postRenderStrategy`, removed APIs, GCR Receiver Secret, kubeconfig file refs, refspec); broken `flux events -A --since=1h` replaced
- `references/security-validation.md`: v2.8.8 CVE note replaced by GHSA-mwcp-qpcg-fr7c (with the 2.8 patch), go-git and CVE-2026-47680 status; Vault/OpenBao Kubernetes auth; SSH commit verification and signing; OCIRepository `trustedRootSecretRef`; allow-webhooks check and `generic-oidc` Receivers; `flux schema` in Policy and CI
- `references/doc-index.md`: controller spec/CRD paths for all seven controllers, served-version rule; flux-schema doc paths fixed; agent skills need the schema plugin
- `scripts/fluxcd-doc-discover.sh`: added helm-controller, image-reflector-controller, image-automation-controller, source-watcher; dropped `api/v1*` prefixes that never matched the .md/.yaml filter (run: 11 repos, exit 0)
- `scripts/fluxcd-version-check.sh`: `BASELINE` default v2.8.8 → v2.9.5
- Manifests: `version` 1.0.1 → 1.1.0 in both `.claude-plugin` and `.codex-plugin` (README row carries no version)

**Evals**: created `evals/evals.json` (the plugin had none): #1 upgrade 2.8 → 2.9 with `v1beta2` objects, #2 post-upgrade strict substitution and post-renderer hooks, #3 CI validation with the schema plugin, #4 HPA drift with `.spec.ignore`. Smoke: pass. Eval #1 answer (workspace `smoke/eval-01-upgrade-2.9.md`) routed SKILL.md → `workflows.md` "Upgrading Flux" and `troubleshooting.md` "After Upgrading to 2.9", and named the removed `v1beta2` APIs, the `flux migrate` Git/cluster order with the cluster-admin caution, image `v1` and Alert/Provider `v1beta3` (no v1), target v2.9.5 with GHSA-mwcp-qpcg-fr7c, Kubernetes 1.34–1.36 vs `flux check --pre`, and the changed 2.9 defaults.
**Checks**: `scripts/check.sh` (fmt --check, lint, validate --fast; nothing skipped locally) and `scripts/test.sh` (15 eval files incl. the new one), both ok; all 15 newly added URLs return 200.

**Code-review follow-up (same run, before merge)**: every finding was re-verified against source first.

- `troubleshooting.md` strict-substitution row: dropped `.spec.postBuild.substituteStrategy` as a "fix" (`fluxcd/pkg` `kustomize/kustomize_varsub.go` substitutes only `if len(vars) > 0 || options.Always`, so it cannot avoid strict failures); added `${var:=}`, `$${var}`, the `kustomize.toolkit.fluxcd.io/substitute: disabled` label/annotation, the `--feature-gates=StrictPostBuildSubstitutions=false` opt-out, and the offline `kustomize build | flux envsubst --strict` check (`flux diff` does a server-side dry-run); eval #2 updated and re-smoked
- `workflows.md` "Upgrading Flux": removals listed per minor (2.7, 2.8, 2.9 from #5572); order scoped to 2.7/2.8; 2.6-or-older routed to #5572's `-v 2.6` flow; Flux Operator note says the Git step stays manual; CI plugin pin `plugins: schema@<version>`; offline `flux envsubst --strict` line
- `troubleshooting.md` GCR row: add `email`/`audience` to the existing Secret (audience default `https://<host>/hook/<sha256(token+name+namespace)>`), regenerate only with `--token`/`--hostname`, SOPS-encrypt the export; Helm v4 note: SSA for new releases only, kstatus `poller` wait for all releases (`helmreleases.md` v1.6.4), `waitStrategy.name: legacy` / `UseHelm3Defaults` remedy; refspec row describes the CRD validation pattern and the lost force inheritance; `.spec.ignore` note says field, and that omitting it is the 2.7/2.8 fix
- `security-validation.md`: GHSA workaround widened to 2.7, 2.8, and 2.9.0–2.9.3 (advisory: "clusters that cannot be upgraded immediately"); `generic-oidc` scoped to OIDC-capable CI callers with upstream's warning to pin identity claims (`receivers.md` v1.9.4)
- `doc-index.md`: agent skills prefer `flux schema` and fall back to a `flux-schema` binary
- eval #3 expected output: the cause is the uninstalled plugin

**Reviewed, not applied**

- AWS CodeCommit `provider: aws` and CodeCommit bootstrap: niche provider; the skill has no per-provider bootstrap list
- ArtifactGenerator `pathPattern` / `commonMetadata`, source-watcher opt-in: monorepo detail beyond the skill's depth; doc-index routes to its spec
- CEL `healthCheckExprs` without `kind`: the skill has no CEL health-check section
- HelmRelease `valuesFrom[].literal`, `chartNameChangeStrategy`, `Drifted` condition: authoring detail beyond the skill's depth
- `.spec.buildMetadata`, prune-failure inventory retention, `flux get --show-source`, `--ns-follows-kube-context`, `--in-memory-build`, `flux trigger receiver`, `flux reconcile` failing fast on kstatus failure: minor CLI/field additions
- Age post-quantum SOPS: no official how-to (open item)
- Flux Mirror plugin, Flux Operator UI, image-reflector `FluxStorage` gate, Bucket GCP `external_account` rejection, notification-controller body/header limits: niche or out of scope
- 2.9.1–2.9.5 bug fixes (SOPS `.ini`, SMP dry-run, in-memory build regression, openapi path regression, empty lines in charts, `spec.images` overrides, packaging, Helm index loading, temp-dir purge, substring panic) and dependency bumps: no guidance change
- Ledger corrections (not skill changes): Helm 4 in helm-controller dates from Flux 2.8, not 2.9; `workflows.md` never carried API version strings (it does now, in "Upgrading Flux")
- Intentional divergence from discussion #5572: the skill's order migrates Git straight to the latest APIs (`flux migrate -f .`) before the upgrade, which is valid from 2.7 or 2.8 because both already serve image `v1` and Alert/Provider `v1beta3` (CRDs at image-reflector v1.0.1 / notification v1.7.1 in Flux v2.7.0). #5572's `-v 2.6` first step plus a post-upgrade `flux migrate -v 2.8 -f .` image step is required from 2.6 (image-reflector v0.35.0 serves only `v1beta1`/`v1beta2`); the skill routes 2.6-or-older users to #5572. The #5572 Job image question (`flux-cli:v2.8.0`) is moot: cluster mode reads the storage version from the live CRDs.

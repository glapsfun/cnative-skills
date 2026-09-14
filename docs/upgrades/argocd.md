---
plugin: argocd
upstream_name: Argo CD
version_source: github-release
upstream_repo: argoproj/argo-cd
upstream_url:
upstream_key:
extra_repos: [argoproj/argo-helm]
version_match: exact
verified_version: v3.5.3
verified_date: 2026-09-14
last_upgrade: 2026-09-14
plugin_version: 1.1.0
check_interval_days: 90
---

# argocd — upgrade memo

Ledger entry created 2026-09-14. The first update run (same day) established the baseline: the skill was authored 2026-06-20 against the v3.4 line (v3.4.4 was current), and is now verified against v3.5.3. `scripts/argocd-version-check.sh` carries the baseline as `SKILL_BASELINE`.

## Sources

- Releases: <https://github.com/argoproj/argo-cd/releases>
- Changelog: <https://github.com/argoproj/argo-cd/blob/master/CHANGELOG.md>
- Upgrade guides: <https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/> (per-minor pages, e.g. `3.4-3.5/`)
- Tested Kubernetes versions: <https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/#tested-versions>
- Docs branch for a given minor (avoids master/3.6-dev leakage): <https://github.com/argoproj/argo-cd/tree/release-3.5/docs>
- Docs: <https://argo-cd.readthedocs.io/en/stable/>
- Helm chart: <https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd>
- Chart index: <https://argoproj.github.io/argo-helm>
- Leads only: <https://blog.argoproj.io/>

## Skill map

- `SKILL.md` — routing, operating rules, quick diagnostics, core patterns; states the verified version
- `references/01-installation-and-concepts.md` — ArgoCD Installation and Core Concepts (install manifests incl. `install-with-hydrator.yaml`, Helm chart pin, K8s support matrix)
- `references/02-crds-and-configuration.md` — ArgoCD CRDs and Application Configuration (Application/AppProject/ApplicationSet specs, sync windows, argocd-cm / argocd-cmd-params-cm keys, §11 Source Hydrator)
- `references/03-cli-reference-and-best-practices.md` — ArgoCD CLI Reference and Best Practices
- `references/04-security-rbac-sso.md` — ArgoCD Security, RBAC, SSO & Secrets Management Reference (§2 TLS incl. repo-server CA path + native mTLS, §9 impersonation + Source Integrity)
- `references/05-troubleshooting-and-advanced.md` — ArgoCD Troubleshooting and Advanced Patterns (§10 per-minor upgrade notes 3.3→3.4, 3.4→3.5; Helm 4 / OCI note in §11)
- `scripts/argocd-diagnostics.sh` — read-only control-plane / app diagnostics (kubectl + argocd CLI only)
- `scripts/argocd-doc-discover.sh` — lists upstream docs/manifests/chart files (depends on `api.github.com/repos/<repo>/git/trees/<ref>`)
- `scripts/argocd-version-check.sh` — latest GitHub release vs `SKILL_BASELINE`, local CLI, live images, CRDs (depends on `api.github.com/repos/argoproj/argo-cd/releases/latest`)
- `evals/evals.json` — 11 evals

## Watch list

- `SKILL.md` — "verified against Argo CD vX (date)" sentence in the intro.
- `references/01-installation-and-concepts.md` — Prerequisites bullet, Version Compatibility Matrix (rows + "verified against" line), Helm chart `--version` pin (chart 10.9.1 = v3.5.3), "stable resolves to" note under install types.
- `references/02-crds-and-configuration.md` — fields flagged Beta: Source Hydrator (§11, Beta since v3.5.0), `destinationServiceAccounts` (Beta since v3.5.0), progressive syncs; Helm 4 statements; `since v3.5` markers on sync windows / valueFiles / ConfigMap keys.
- `references/03-cli-reference-and-best-practices.md` — CLI flags (`argocd app sync/diff` options).
- `references/04-security-rbac-sso.md` — RBAC policy syntax, Dex/OIDC config keys; `--repo-server-strict-tls` deprecation ("may be removed in v3.6" — check each release); `signatureKeys` removal ("next major").
- `references/05-troubleshooting-and-advanced.md` — §10 "Upgrade Notes" subsections (add one per new minor), supported-minor window sentence.
- `scripts/argocd-version-check.sh` — `SKILL_BASELINE` constant.
- Manifest descriptions and the README plugin row — no version stated today.

## Open items

- 2026-09-14: SCM-provider generator `excludeArchivedRepos` / `includeArchivedRepos` (v3.5) not added — skill has no SCM-provider section in ref 05 §15; add one when ApplicationSet coverage is next revised. <https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-SCM-Provider/>
- 2026-09-14: v3.5.0 adds `argocd` CLI support for Source Integrity policies (#26997); exact `argocd proj` flags not found in the release-3.5 command reference, so ref 04 says "manifest or CLI" without syntax. Verify and document.
- 2026-09-14: unconfirmed leads from the v3.5 blog (HTTP 403 to fetch): "ApplicationSets fully stable / concurrency configurable in the ApplicationSet spec". release-3.5 docs still label progressive syncs Beta and the CRD has no concurrency field. Re-check on the next run. <https://blog.argoproj.io/>
- 2026-09-14: whether `argocd-cm` `helm.versions` still selects alternate binaries under Helm 4 is undocumented on release-3.5; the example was removed from ref 02 rather than rewritten.
- 2026-09-14: built-in `toggle-auto-sync` resource action (#26477) and the new health checks (Karpenter NodeClaim, GatewayClass, BackendTLSPolicy, Gardener Shoot, VictoriaMetrics) not documented — low demand; add to ref 05 §4 if users ask.
- 2026-09-14: `references/05` still teaches `argocd app wait` without the v3.4.3 "returns immediately when already in desired state" behaviour — minor, fold in next run.

## Upgrade log

### 2026-09-14 — v3.4.4 → v3.5.3 (plugin 1.0.0 → 1.1.0)

Baseline established: skill authored 2026-06-20 against the v3.4 line; `verified_version` set for the first time.
Range: 13 releases (v3.4.1 … v3.4.9 patch line; v3.5.0 2026-08-04, v3.5.1, v3.5.2, v3.5.3 2026-09-14).

Sources consulted:

- <https://github.com/argoproj/argo-cd/releases> — release notes v3.4.1 … v3.5.3 (via `cupgrade-releases.sh --since v3.4.0 --notes`)
- <https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.4-3.5/> — Helm 4, strict-tls deprecation, mTLS, impersonation, SSH known_hosts, React 19 extensions, EventList
- <https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.3-3.4/> — cluster version format, Missing health rule
- <https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/#tested-versions> — K8s matrix
- <https://argo-cd.readthedocs.io/en/stable/user-guide/helm/> — Helm version, valueFiles globs
- <https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_repo_add/> — `--insecure-oci-force-http`
- <https://argo-cd.readthedocs.io/en/stable/user-guide/source-integrity/>, <https://argo-cd.readthedocs.io/en/stable/user-guide/source-integrity-git-gpg/>, <https://argo-cd.readthedocs.io/en/stable/user-guide/gpg-verification/> — Source Integrity
- <https://argo-cd.readthedocs.io/en/stable/operator-manual/tls/>, <https://argo-cd.readthedocs.io/en/stable/operator-manual/mtls/> — CA path flags, `argocd-repo-server-mtls`
- <https://argo-cd.readthedocs.io/en/stable/operator-manual/app-sync-using-impersonation/> — impersonation Beta, `enforced`
- <https://argo-cd.readthedocs.io/en/stable/user-guide/source-hydrator/> — hydrator spec, `repository-write`, `hydrateTo`
- <https://argo-cd.readthedocs.io/en/stable/user-guide/sync_windows/#sync-overrun> — `syncOverrun`
- <https://argo-cd.readthedocs.io/en/stable/operator-manual/argocd-cm.yaml>, <https://argo-cd.readthedocs.io/en/stable/operator-manual/argocd-cmd-params-cm.yaml> — new keys
- <https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/microsoft/> — Entra groups overflow; <https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#existing-oidc-provider> — `refreshTokenThreshold`, `userInfoURL`
- <https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories> — Azure DevOps Service Principal fields
- <https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/Chart.yaml> — chart 10.9.1 / appVersion v3.5.3
- Docs read from the `release-3.5` branch raw markdown to avoid 3.6-dev content.

Applied:

- `SKILL.md` — "verified against v3.5.3" sentence; routing lines for TLS/mTLS + Source Integrity + impersonation (ref 04) and Source Hydrator + syncOverrun + Helm 4 (ref 02); dead `docs/research-argocd.md` pointer → `docs/upgrades/argocd.md`; reference table updated
- `references/01` — prerequisites + matrix: v3.5 row (K8s v1.33–v1.36), three-minor support window, v3.2 EOL, "verified against" line; Helm chart pin 7.x → 10.9.1 with appVersion warning; new `install-with-hydrator.yaml` install type; note that `stable` resolves to v3.5.3
- `references/02` — Helm `version: v3` marked ignored (Helm 4); valueFiles glob example; `syncOverrun` field + rules; AppProject spec stubs for `destinationServiceAccounts` and `sourceIntegrity`; argocd-cm: `helm.versions` example removed, impersonation keys, webhook jitter keys, hydrator templates, `timeout.reconciliation: 0` note; cmd-params: webhook workers, glob cache, hydration processors, repo-server CA/mTLS paths; new §11 Source Hydrator; hydrator stub in Application spec; TOC
- `references/03` — `-N/--app-namespace` on `app sync` / `app diff`; `--insecure-oci-force-http` example + flag row, `--upsert` row; `proj add-signature-key` deprecation subsection; `proj windows add --sync-overrun`
- `references/04` — "Strict Inter-Component TLS Validation" rewritten around `--repo-server-ca-cert-path` / `*.repo.server.ca.cert.path` with the deprecated flags kept as "before v3.5"; new "Native mTLS to the Repo Server"; OIDC `userInfoURL`, `refreshTokenThreshold`; Entra `enableUserGroupOverageClaim` / `graphApiEndpoint`; new §9 subsections "Sync Impersonation with destinationServiceAccounts (Beta)" and "Source Integrity: Commit Signature Verification"
- `references/05` — SSH known_hosts v3.5 behaviour; Azure DevOps Service Principal secret; `timeout.reconciliation: 0` + webhook jitter/workers/glob cache in Performance Tuning; Helm 4 / OCI plain-HTTP breaking note; valueFiles glob version label corrected (was "v2.9+", is v3.5 / backport v3.4.1) + de-dup rule; §10 examples moved to 3.x, supported-minor window, new "Upgrade Notes: v3.4 → v3.5" and "v3.3 → v3.4" subsections
- `scripts/argocd-version-check.sh` — `SKILL_BASELINE="v3.5.3"`, printed next to the upstream latest with a hint when upstream is newer
- Manifests — `version` 1.0.0 → 1.1.0 in both `.claude-plugin` and `.codex-plugin` (README row carries no version)

Evals: changed #5 (chart 10.x); added #6 Source Integrity, #7 Helm 4 plain-HTTP OCI, #8 strict-tls → CA path / mTLS, #9 impersonation, #10 syncOverrun, #11 Source Hydrator. Smoke: pass — eval #6 answer (workspace `smoke/eval-06-source-integrity.md`) routed via SKILL.md to ref 04 §9 and named `spec.sourceIntegrity.git.policies`, `gpg.mode: strict`, and the `signatureKeys` auto-conversion/deprecation.
Checks: `scripts/check.sh` (fmt --check, lint, validate --fast — nothing skipped locally; yamllint line-length warnings are pre-existing in untouched files) and `scripts/test.sh` — both ok.

Reviewed, not applied:

- v3.4.2–v3.4.5, v3.4.7–v3.4.9, v3.5.2, v3.5.3 — bugfix/CVE-only patch releases; no guidance change
- v3.4.6 OIDC refresh-token fix and Entra `uti` claim — folded into the `refreshTokenThreshold` note; no separate guidance
- 3.3→3.4 cluster version format `vMajor.Minor.Patch` — skill example already used the correct form; summarised in the new 3.3→3.4 notes only
- SCM-provider archived-repo filters — no SCM section to host it (open item)
- `toggle-auto-sync` action, new health checks, ApplicationSet UI additions, annotation/operation filters, per-app banner, SBOM layout, Renovate cleanup — UI/tooling; no operator guidance
- `applicationsetcontroller.concurrent.reconciliations.max`, hydrator `commit.author.*` — already existed in 3.4 docs, not new
- OpenTelemetry metric renames / go-oidc signature-first (3.3→3.4) — predate the baseline and touch no skill text

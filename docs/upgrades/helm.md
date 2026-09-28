---
plugin: helm
upstream_name: Helm
version_source: github-release
upstream_repo: helm/helm
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: v4.3.0
verified_date: 2026-09-28
last_upgrade: 2026-09-28
plugin_version: 1.1.0
check_interval_days: 90
also_verified: [v3.22.0]
---

# helm — upgrade memo

Dual-line skill: Helm 4 is the default assumption (verified v4.3.0), and every flag or behaviour that differs keeps its Helm 3 form (verified v3.22.0, the final Helm 3 minor). The status script tracks only the Helm 4 line; check the Helm 3 line by hand (`cupgrade-releases.sh helm/helm --since v3.22.0`) until Helm 3 security support ends, then drop the Helm 3 wording in a dedicated run.

## Sources

- Releases: <https://github.com/helm/helm/releases> (both lines interleave; v3.x and v4.x tags)
- Docs (Helm 4, unversioned): <https://helm.sh/docs/>
- Helm 4 overview / changes from Helm 3: <https://helm.sh/docs/overview/>
- Changelog: <https://helm.sh/docs/changelog/>
- CLI reference (Helm 4): <https://helm.sh/docs/helm/>
- Docs (Helm 3, versioned): <https://helm.sh/docs/v3/> (same sub-paths; bannered "no longer actively maintained")
- Version skew: <https://helm.sh/docs/topics/version_skew/>, <https://helm.sh/docs/v3/topics/version_skew/>
- Plugins (Helm 4): <https://helm.sh/docs/plugins/overview/>, <https://helm.sh/docs/plugins/user/>, <https://helm.sh/docs/plugins/migrate/>
- Chart template guide: <https://helm.sh/docs/chart_template_guide/> (function list: `/chart_template_guide/function_list/`)
- Chart best practices: <https://helm.sh/docs/chart_best_practices/>
- Registries: <https://helm.sh/docs/topics/registries/>
- HIPs (design detail; confirm the feature shipped): <https://github.com/helm/community/tree/main/hips> (0020 charts v3, 0022 wait, 0023 SSA, 0026 plugins)
- Source at tag, when docs lag: `helm/helm@<tag>` (e.g. `pkg/action/upgrade.go`, `pkg/action/install.go`, `pkg/cmd/*.go`)
- Local binary `helm <cmd> --help` at the verified version: acceptable for flag names and defaults
- Sprig functions: <https://masterminds.github.io/sprig/>
- helm-diff install (Helm 4 signed tarball): <https://github.com/databus23/helm-diff#install>
- Artifact Hub: <https://artifacthub.io/>
- Leads only: <https://helm.sh/blog/> (Helm 3 EOL post: <https://helm.sh/blog/helm-v3-end-of-life>)

## Skill map

- `SKILL.md`: 120 lines; version framing (Helm 4 default, Helm 3 names), render-first rule, dry-run semantics, routing, core rules
- `references/01-chart-anatomy-and-authoring.md`: Chart.yaml (strict parse, apiVersion v2/v3), values.yaml, values.schema.json drafts, dependencies, hooks (log policy), packaging
- `references/02-templating-go-and-sprig.md`: Go text/template + Sprig; version-gated functions
- `references/03-cli-and-release-lifecycle.md`: flags table (Helm 4 / Helm 3 names), values precedence and reuse table, inspection, helm-diff, OCI, § "Helm 4 vs Helm 3" + migration checklist
- `references/04-debugging-and-validation.md`: render ladder, dry-run detail, offline capabilities, errors, runtime, "Apply, wait, and ownership failures", stuck releases
- `references/05-best-practices.md`: values, labels, workload hygiene, CRDs, RBAC, checklist
- `references/06-discovery-and-repos.md`: search, repos, show, pull, OCI (digest pinning), dependencies
- `scripts/helm-chart-validate.sh`: lint --strict + template + yamllint/kubeconform (read-only)
- `scripts/helm-doc-discover.sh`: doc links for Helm 4 and Helm 3 trees, plugins, skew
- `scripts/helm-release-debug.sh`: status/history/get values/hooks/manifest + events
- `scripts/helm-version-check.sh`: client line (3 vs 4), `SKILL_BASELINE`/`SKILL_BASELINE_V3`, context, plugins, validators
- `evals/evals.json`: 8 evals

## Watch list

- `SKILL.md` intro: "verified against v4.3.0 and v3.22.0, 2026-09-28", "Helm 3 is frozen at 3.22.x and receives security fixes only".
- `SKILL.md` "First step": Kubernetes skew sentence (4.3.x and 3.22.x: 1.34–1.37).
- `scripts/helm-version-check.sh`: `SKILL_BASELINE` (`v4.3.0`), `SKILL_BASELINE_V3` (`v3.22.0`), the per-major hint lines.
- `references/03` § "Helm 4 vs Helm 3": flag table, minimum-patch line (at least v4.1.4, prefer v4.3.0), 4.3.0-only features (`rollback --description`, `history --show-rollback-revision`, uninstall ownership check).
- `references/03` / `04`: `--wait` strategies and kstatus behaviour (HIP-0022; fixes still landing in patches).
- `references/01`: chart `apiVersion: v3` status (experimental, not renderable at 4.3.0); JSON Schema draft support.
- `references/02` / `04`: version-gated template functions (`toYamlPretty` 3.17, `mustToYaml` Helm 4, `duration*` 4.3.0).
- `scripts/helm-doc-discover.sh`: helm.sh docs layout (unversioned = Helm 4, `/docs/v3/` = Helm 3).
- Helm 3 end of life: once security support ends, remove "Helm 3:" alternates in a separate run and drop `also_verified`.
- Cross-plugin: `kubernetes-operator` `references/helm.md` and its Helm baseline; `fluxcd` helm-controller Helm 4 notes.

## Open items

- 2026-09-28: Helm 3 security-fix end date conflicts between sources. The maintainers' blog (2026-06-02) says final minor 2026-09-09 and security fixes through 2027-02-10; `helm/helm` README at v4.3.0 (and `main`) still says bug fixes to 2026-07-08, security to 2026-11-11. The v3.22.0 release (2026-09-10) matches the blog. The skill states no date; re-check at the next run.
- 2026-09-28: Bitnami chart examples in `references/06` and eval #4 (`https://charts.bitnami.com/bitnami`, `oci://registry-1.docker.io/bitnamicharts/postgresql`) may be stale after Bitnami catalog changes; outside helm/helm, not verified.
- 2026-09-28: helm-diff behaviour on server-side-apply releases (diff accuracy) not verified.
- 2026-09-28: `helm uninstall` ownership check (4.3.0) is documented only in the v4.3.0 release notes and source (`pkg/action/validate.go`); switch the citation to the docs page when `helm_uninstall` documents it.
- 2026-09-28: "custom template functions through plugins" (Helm 4 overview page) has no CLI/plugin mechanism in v4.3.0 source (SDK field only); do not teach it until one ships.
- 2026-09-28: `scripts/helm-chart-validate.sh` could pass `--kube-version`/`--api-versions` through to `lint`/`template` for offline capability checks; feature work, not drift.
- 2026-09-28 (cross-plugin): `kubernetes-operator` states "Helm docs baseline: v4.2.0"; refresh to v4.3.0 and align its `--wait` wording with the strategies (`hookOnly` default, bare `--wait` = kstatus `watcher`, `legacy`). Recorded in its memo.

## Upgrade log

### 2026-09-28: Helm 3 (~v3.13) → v4.3.0, Helm 3 line checked at v3.22.0 (plugin 1.0.0 → 1.1.0)

Baseline established: the skill was written against Helm ~3.13 knowledge (newest cited feature `--dry-run=server`, 3.13.0; nothing from 3.14+; no Helm 4 text). `verified_version` set for the first time.
Range: 45 Helm 3 tags after v3.13.0 (v3.14.0 2024-01-17 … v3.22.0 2026-09-10, the final Helm 3 minor) and 15 Helm 4 tags (v4.0.0 2025-11-12 … v4.3.0 2026-09-09). Research split by release line (two subagents), merged in the workspace plan.

**Sources consulted**

- <https://github.com/helm/helm/releases>: notes v3.13.1 … v3.22.0 and v4.0.0 … v4.3.0 (via `cupgrade-releases.sh helm/helm --since v3.13.0 --notes`)
- <https://helm.sh/docs/overview/>: renamed/deprecated flags, SSA, post-renderer plugins, registry login, multi-document values, upgrade checklist
- <https://helm.sh/docs/helm/helm_install/>, `helm_upgrade/`, `helm_rollback/`, `helm_list/`, `helm_lint/`, `helm_status/`, `helm_template/`, `helm_version/`, `helm_plugin_install/`, `helm_history/`: Helm 4 flags
- <https://helm.sh/docs/v3/helm/helm_install/>, `helm_upgrade/`, `helm_lint/`, `helm_template/`, `helm_list/`, `helm_get_metadata/`, `helm_registry_login/`, `helm_dependency_update/`, `helm_search_repo/`: Helm 3 flags and versions
- <https://helm.sh/docs/topics/version_skew/>, <https://helm.sh/docs/v3/topics/version_skew/>: Kubernetes support per minor
- <https://helm.sh/docs/plugins/overview/>, <https://helm.sh/docs/plugins/user/>, <https://helm.sh/docs/plugins/migrate/>: plugin types, verification, post-renderer break
- <https://helm.sh/docs/v3/topics/registries/>, <https://helm.sh/docs/topics/registries/>: digest installs
- <https://helm.sh/docs/v3/chart_template_guide/values_files/>: `null` deletes a default
- <https://helm.sh/docs/chart_template_guide/function_list/>, <https://helm.sh/docs/v3/chart_template_guide/function_list/>: `toYamlPretty`, `fromToml`, `mustToYaml`, duration helpers
- <https://helm.sh/docs/v3/topics/charts/>: schema validation commands, `--skip-schema-validation`
- <https://github.com/helm/community/blob/main/hips/hip-0022.md>, <https://github.com/helm/community/blob/main/hips/hip-0023.md>, <https://github.com/helm/community/blob/main/hips/hip-0020.md>: wait strategies, SSA, charts v3
- <https://github.com/helm/helm/security/advisories/GHSA-q5jf-9vfq-h4h7>: plugin `.prov` fail-open (fixed v4.1.4)
- <https://github.com/helm/helm/releases/tag/v4.1.3>, `v4.1.4`, `v4.2.1`, `v4.3.0`, `v3.17.1`, `v3.18.0`, `v3.19.0`, `v3.20.1`, `v3.21.0`, `v3.22.0`: regressions, EOL wording, per-version fixes
- `helm/helm@v4.3.0` `pkg/action/upgrade.go` (`reuseValues`), `pkg/action/install.go` (dry-run branches), `pkg/action/validate.go` (uninstall ownership), `pkg/release/v1/hook.go` (hook log policy): read directly
- `helm/helm@v3.22.0` `pkg/kube/client.go` (`--force` = Replace), `pkg/cli/environment.go` (namespace resolution), `go.mod` + `pkg/chartutil/jsonschema.go` (schema library, 2020-12 default)
- Local `helm v4.3.0+gbec5b06`: `--help` extracts, deprecated-alias warnings, `plugin install --verify`, strict `Chart.yaml` lint, `--kube-version`/`--api-versions` rendering (workspace `helm4-local-help.txt`)
- <https://github.com/databus23/helm-diff#install>: Helm 4 signed-tarball install
- <https://helm.sh/blog/helm-v3-end-of-life>: lead only; Helm 3 EOL dates (see Open items)

**Applied**

- `SKILL.md`: version framing (Helm 4 default, Helm 3 frozen at 3.22.x, renamed flags, "verified against v4.3.0 and v3.22.0"); Kubernetes skew sentence; dry-run paragraph corrected (server = live capabilities, `lookup`, live schema validation, existing-object check; no admission; explicit `--dry-run=client`; `--hide-secret`); values rule: upgrade drops earlier overrides, `--reset-then-reuse-values`; safety rule uses `--rollback-on-failure`/`--atomic`, `--force-replace`/`--force`, `--force-conflicts`, `--take-ownership`; hand-edit rule notes SSA conflicts; routing lines for 03 (reuse flags, take-ownership, helm-diff), new "Helm 4 vs Helm 3" route, 04 Helm 4 failures, doc tree; `helm create` HTTPRoute
- `references/03`: flags table corrected (`--force` is PUT replace; `--wait-for-jobs` needs `--wait`; namespace follows kube context) with Helm 4/3 names and new rows (`--reset-then-reuse-values`, `--take-ownership`, `--skip-schema-validation`, `--hide-secret`); values-precedence gotcha corrected into a reuse-flag table + `null` deletion; `helm get metadata` + `helm list` line difference; helm-diff Helm 4 install; OCI host-only login, digest pin, per-command credentials, `--plain-http`; new § "Helm 4 vs Helm 3" (comparison table, migration checklist, minimum patch levels, 4.3.0 rollback/history flags)
- `references/04`: dry-run bullets corrected + `kubectl apply --dry-run=server` for admission; `--hide-secret`; offline `--kube-version`/`--api-versions`; error rows for version-gated functions and strict `Chart.yaml`; new "Apply, wait, and ownership failures" table (SSA conflict, kstatus timeout, invalid ownership metadata, uninstall leftovers, `Pulled:` in stdout, hook log policy); values checklist step 3 corrected, step 5 `null`; stuck release uses new flag name, "Helm 3 and Helm 4" Secrets, `rollback --description`
- `references/01`: `helm create` HTTPRoute + probes in values; `apiVersion` comment (v2 for Helm 3 and 4); strict `Chart.yaml` parse and charts v3 status; schema drafts (2020-12 default since 3.18.5), remote `$ref`, `--skip-schema-validation`; `helm.sh/hook-output-log-policy`
- `references/02`: `toYamlPretty`/`mustToYaml` on the `toYaml` row; `function "X" not defined` row lists version-gated functions
- `references/05`: only CRDs in `crds/` (Helm 4 lint error)
- `references/06`: `--fail-on-no-result`; host-only login; digest pin example and advice
- `scripts/helm-version-check.sh`: `SKILL_BASELINE="v4.3.0"`, `SKILL_BASELINE_V3="v3.22.0"`, per-major hint; helm-diff suggestion points to the Helm 4 install on Helm 4 (the git-URL command fails there). Tested with local v4.3.0 and a v3.22.0 stub
- `scripts/helm-doc-discover.sh`: Helm 4 overview, changelog, version skew, Helm 3 `/docs/v3/` tree, plugin pages; every printed URL returned 200
- `scripts/helm-chart-validate.sh`, `scripts/helm-release-debug.sh`: no change needed (both run on v4.3.0; `lint --strict` is stricter on Helm 4, documented in 01/04/05)
- Manifests: `version` 1.0.0 → 1.1.0 in both `.claude-plugin` and `.codex-plugin` (README row carries no version)

**Evals**: changed #3 (`--rollback-on-failure` / `--atomic`); added #6 (CI migration to Helm 4), #7 (upgrade dropped earlier `--set` overrides), #8 (helm-diff install fails on Helm 4 signature verification). Smoke: pass. Eval #6 answer (workspace `smoke/eval-06-helm4-ci-migration.md`) routed SKILL.md → `03` § "Helm 4 vs Helm 3" and `04` failures table, and named `--rollback-on-failure`, `--force-replace`, `--wait` strategies with kstatus `list`/`watch` RBAC and `--wait=legacy`, `--server-side=auto` with `APPLY_METHOD`, `--force-conflicts` (not with `--force-replace`), plugin verification, and the v4.1.4 minimum.
**Checks**: `scripts/check.sh` (fmt --check, lint, validate --fast; nothing skipped locally; yamllint line-length warnings are pre-existing in untouched `agents/openai.yaml` files) and `scripts/test.sh`, both ok.

**Reviewed, not applied**

- Charts v3 (`apiVersion: v3`) feature set: undocumented and not renderable at 4.3.0; skill says "experimental, keep v2"
- Custom template functions "through plugins": SDK-only at v4.3.0 (open item)
- Wasm runtime, plugin `plugin.yaml` apiVersion/type/runtime fields, `helm plugin package`/`verify`: plugin-author topics; skill covers plugin use
- `mustToToml`, duration helpers beyond a mention: niche; covered by the version-gated functions row
- `--hide-notes` (3.16), `helm repo add/update --timeout` (3.20), `helm repo list --no-headers` (4.1): minor flags, no guidance change
- `--qps`, content cache, coloured output, reproducible archives / `SOURCE_DATE_EPOCH`, SDK package moves, slog: no chart-user guidance
- Per-CVE patch releases (3.14.1 … 3.20.2, 4.1.4): folded into "latest 3.22.x" / "at least v4.1.4"
- kstatus observedGeneration checks, `tpl` speedups, CRD-install and `Files.Lines` panics, `uninstall --keep-history` status fix: bug fixes, no guidance change
- `.Capabilities.KubeVersion.GitVersion` vendor-suffix regression (3.19.0 … 4.0.x): transient; fixed in 4.1.0
- 3.16.0 "adopt unmanaged resources": reverted in 3.16.1, superseded by `--take-ownership`
- ORAS v2 OCI regressions in 3.18.x: fixed by 3.19.0; skill recommends current patches

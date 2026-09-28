# The helm CLI and release lifecycle

A **release** is an instance of a chart installed into a cluster, tracked by Helm in a per-revision Secret (default driver) in the release namespace. Every `upgrade`/`rollback` creates a new revision.

## Core lifecycle commands

```bash
helm install my-release ./mychart -n my-ns --create-namespace
helm install my-release oci://registry/charts/mychart --version 1.2.3
helm upgrade my-release ./mychart -n my-ns -f prod.yaml
helm upgrade --install my-release ./mychart -n my-ns      # install if absent, else upgrade (idempotent — ideal for CI)
helm rollback my-release 3 -n my-ns                        # revert to revision 3
helm uninstall my-release -n my-ns                         # remove (use --keep-history to retain revision records)
```

Key flags that change behavior meaningfully:

| Flag | Effect |
|------|--------|
| `--rollback-on-failure` (Helm 4) / `--atomic` (Helm 3) | On failure, roll an upgrade back to the last successful revision (or uninstall a failed install) instead of leaving a broken/partial release. Implies `--wait`. Strongly recommended for upgrades. |
| `--wait` | Block until resources are ready before reporting success. On Helm 4 bare `--wait` means the kstatus `watcher` strategy (see "Helm 4 vs Helm 3"). `--wait-for-jobs` also waits on Jobs, but only when `--wait` is on (a rollback flag turns it on). |
| `--timeout 5m` | How long Helm waits for resources, hooks, and Jobs before failing (default 5m). |
| `--install` | (on `upgrade`) create the release if it doesn't exist — the idempotent CI pattern. |
| `--force-replace` (Helm 4) / `--force` (Helm 3) | Update objects by full replacement (PUT) instead of a patch. Can wipe fields other controllers set and still fails on immutable fields; avoid unless a patch cannot apply. |
| `--cleanup-on-fail` | Delete newly-created resources if an upgrade fails. |
| `--reuse-values` / `--reset-values` / `--reset-then-reuse-values` | How `upgrade` treats the previous release's values. The default is a common surprise; see precedence below. |
| `--take-ownership` (3.17+) | Adopt existing objects that lack Helm's ownership metadata instead of failing with `invalid ownership metadata`. State-changing: confirm no other release or tool owns them. |
| `--skip-schema-validation` (3.16+) | Skip `values.schema.json` checks (e.g. air-gapped installs whose schema has remote `$ref`). An escape hatch, not a default. |
| `--hide-secret` (3.15+) | With `--dry-run`, leave Secrets out of the printed manifest. |
| `-n` / `--namespace`, `--create-namespace` | Target namespace. Without `-n`, Helm uses `HELM_NAMESPACE`, then the kubeconfig context's namespace, then `default`, so a context switch silently retargets. Be explicit. |

## Values precedence (later wins)

When the same key is set in multiple places, the **last** source wins, evaluated in this order:

1. Chart's own `values.yaml`
2. Parent chart values (for subcharts) and `global` values
3. `-f` / `--values` files, applied **left to right**
4. `--set`, `--set-string`, `--set-file`, `--set-json` (highest precedence)

Gotchas that cause "my override didn't take effect":

- **`--set` replaces entire arrays**, it does not merge them. To change one list element you must re-supply the whole list (often easier via a `-f` file).
- **`helm upgrade` forgets earlier overrides as soon as you pass any new ones.** Which values carry over depends on the flag:

  | `helm upgrade` with | Values used |
  |---------------------|-------------|
  | no flag, no `-f`/`--set` | previous release's user values, unchanged |
  | no flag, any `-f`/`--set` | new chart defaults + only this command's overrides; **earlier overrides are dropped** |
  | `--reuse-values` | previous user values + this command's overrides, rendered against the **old** chart's defaults: after a chart bump, new default keys are missing (a common nil-pointer cause) |
  | `--reset-then-reuse-values` (3.14+) | new chart defaults + previous user values + this command's overrides; usually what people mean after a chart version bump |
  | `--reset-values` | new chart defaults + this command's overrides only |

  The robust pattern is to keep every override in committed `-f` files and pass them on every upgrade.
- **To delete a default, set it to `null`** (`--set livenessProbe.httpGet=null`). Reliable for subchart and empty-map defaults since 3.20.1; older clients silently keep some of them.

Inspect what actually applied:

```bash
helm get values my-release -n my-ns        # user-supplied values
helm get values my-release -n my-ns -a     # all computed values (defaults + overrides)
```

## Inspection and history

```bash
helm list -n my-ns                  # releases in a namespace (-A for all namespaces)
helm status my-release -n my-ns     # current state + NOTES
helm history my-release -n my-ns    # every revision with status (deployed/superseded/failed/pending-*)
helm get manifest my-release -n my-ns   # the exact YAML Helm applied for the current revision
helm get metadata my-release -n my-ns   # chart + app version, status, revision (Helm 4 adds APPLY_METHOD); -o json for scripts
helm get hooks my-release -n my-ns
helm get notes my-release -n my-ns
```

`helm list` differs by line: Helm 3 shows only deployed and failed releases unless you add `-a`; Helm 4 shows every status by default and removed `-a` (filter with `--pending`, `--failed`, `--deployed`, …).

`helm get manifest` is the source of truth for "what did Helm actually deploy" — far more reliable than re-rendering, because it reflects the values that were really in effect.

## Local / authoring commands

```bash
helm create mychart                 # scaffold a new chart
helm lint ./mychart --strict        # static checks; --strict promotes warnings to errors
helm template rel ./mychart         # render manifests to stdout (no cluster needed)
helm package ./mychart              # build a .tgz
helm show values ./mychart          # print a chart's default values
helm show chart ./mychart           # print Chart.yaml
```

## helm test

If the chart has templates under `templates/tests/` annotated as `helm.sh/hook: test`, run them against a live release as smoke tests:

```bash
helm test my-release -n my-ns
```

Each test is a Pod; success = the Pod completes 0. Use it to validate connectivity/health post-install.

## helm diff (plugin)

The `helm-diff` plugin previews what an upgrade would change before you apply it — invaluable in review and CI:

```bash
helm plugin install https://github.com/databus23/helm-diff     # Helm 3
helm diff upgrade my-release ./mychart -n my-ns -f prod.yaml
```

On Helm 4 that install command fails with `plugin source does not support verification`: `helm plugin install` verifies signatures by default, and a git URL cannot be verified. Either follow the helm-diff README's Helm 4 steps (import the maintainer's key, install the signed release tarball, which ships a `.prov`), or add `--verify=false` as an explicit, user-approved opt-out. Local directories install as unverified dev plugins.

## OCI registries

Helm 3.8+ treats OCI registries as first-class:

```bash
helm registry login registry.example.com          # host only; Helm 4 fails on oci:// or a repository path
helm push mychart-1.2.3.tgz oci://registry.example.com/charts
helm install my-release oci://registry.example.com/charts/mychart --version 1.2.3
helm install my-release oci://registry.example.com/charts/mychart@sha256:<digest>   # immutable pin (3.17+)
helm pull oci://registry.example.com/charts/mychart --version 1.2.3
```

No `helm repo add` needed for OCI — reference the `oci://` URL directly. A digest pins the exact artifact, which a re-pushed tag cannot silently change. `helm push`, `helm package`, and `helm dependency update/build` accept `--username`/`--password` and TLS flags (3.17+), so CI can skip `registry login`. A plain-HTTP registry needs `--plain-http`: Helm 3.18–3.22 retry over HTTP silently, Helm 4 does not.

## Helm 4 vs Helm 3

Check `helm version --short` first (`v4.x` or `v3.x`). Helm 4 reads and upgrades Helm 3 releases in place (same `sh.helm.release.v1.*` Secrets), and `apiVersion: v2` charts work unchanged. What changes is the CLI surface and how objects are applied and waited on:

| Area | Helm 4 | Helm 3 |
|------|--------|--------|
| Roll back on failure | `--rollback-on-failure` | `--atomic` (Helm 4 accepts it with a deprecation warning; `helm install --atomic` is an unknown flag on 4.0.0–4.1.1) |
| Replace objects | `--force-replace` | `--force` (deprecated alias in Helm 4) |
| Apply method | server-side apply for new installs (`--server-side`, default `true`); `upgrade`/`rollback` default `--server-side=auto`, which keeps the release's previous method | client-side three-way merge patch |
| Field ownership conflicts | fail the operation; `--force-conflicts` takes the fields (cannot combine with `--force-replace`) | not detected; Helm's patch wins |
| `--wait` | a strategy: omitted = `hookOnly` (hooks only, like Helm 3 without `--wait`); bare `--wait` = `watcher` (kstatus: every object incl. custom resources, needs `list` + `watch` RBAC on all of them); `--wait=legacy` = the Helm 3 poller | polls built-in workload readiness |
| Dry run | `--dry-run=none\|client\|server`; bare `--dry-run` and `helm template --validate` deprecated (use `--dry-run=client` / `--dry-run=server`) | `--dry-run`, `--dry-run=client\|server` |
| Removed | `upgrade`/`rollback --recreate-pods` (use a checksum annotation), `list -a`, `status --show-desc`/`--show-resources` (always shown), `repo add --no-update`, `version -c`, `helm lint` without a path | present |
| Post-renderer | `--post-renderer <name>` of an installed `postrenderer/v1` plugin, arguments via `--post-renderer-args`; hooks are post-rendered too | path to any executable; hooks skipped |
| Plugins | `helm plugin install` verifies signatures (tarball/OCI sources need a `.prov`); Helm 3 plugins still run, listed as `legacy` | no verification |
| Values files | may hold several YAML documents (`---`), merged in order; `--set-json` also takes a whole JSON object | one document per file |
| `uninstall` | 4.3.0+: skips objects whose `app.kubernetes.io/managed-by` / `meta.helm.sh/release-*` metadata no longer points at this release, and lists them | deletes everything in the manifest |

Migrating CI or a team to Helm 4:

1. Rename `--atomic` → `--rollback-on-failure` and `--force` → `--force-replace` in scripts (old names warn; `install --atomic` breaks below 4.1.3).
2. Decide the wait strategy. `--rollback-on-failure` and bare `--wait` now use kstatus: grant the deploy identity `list`/`watch` on every kind the chart ships, or pass `--wait=legacy` to keep Helm 3 semantics.
3. Existing releases stay on client-side apply until `helm upgrade --server-side=true`; `helm get metadata` shows `APPLY_METHOD`. After switching, fields owned by an HPA, an operator, or a past `kubectl edit` conflict: drop the field from the chart, or `--force-conflicts` once you have confirmed Helm should own it.
4. Reinstall plugins with verification and convert executable post-renderers into `postrenderer/v1` plugins.
5. Re-test OCI registry auth and any chart using Helm 4-only features (multi-document values, `mustToYaml`), which break for teammates still on Helm 3.
6. Run at least v4.1.4 (fixes plugin `.prov` fail-open and chart-extraction advisories); prefer v4.3.0, which fixes `Pulled:`/`Digest:` lines leaking into `helm template`/`helm show` stdout for OCI charts (4.2.1–4.2.4) and values files silently ignored at an exact 4096-byte boundary.

Helm 4.3.0 also adds `helm rollback --description "<reason>"` and `helm history --show-rollback-revision`.

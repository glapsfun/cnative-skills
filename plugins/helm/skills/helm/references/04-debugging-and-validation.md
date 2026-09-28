# Debugging and validation

First classify the failure: **render-time** (chart won't produce valid YAML — no cluster needed) or **runtime** (release misbehaves — needs live evidence). Mixing them up wastes time.

## Render-time: the local debugging ladder

Work from cheapest/most-local to most-involved:

```bash
helm lint ./mychart --strict          # 1. static analysis; --strict fails on warnings too
helm template rel ./mychart           # 2. render everything; read the actual YAML
helm template rel ./mychart -f prod.yaml --set image.tag=1.2.3   # 3. render with real values
helm template rel ./mychart -s templates/deployment.yaml         # 4. render ONE file to isolate
helm install rel ./mychart --dry-run=server --debug              # 5. render + validate against the live API
```

- **`--debug`** prints the computed values and the full rendered manifest, even alongside errors — your highest-signal tool.
- **`--dry-run=server` vs `--dry-run=client`** (Helm 3.13+): `server` is what makes `lookup` return live objects. Whether the client mode touches the cluster depends on command and line:

  | Command | `--dry-run=client` | `--dry-run=server` |
  |---------|--------------------|--------------------|
  | `helm install`, Helm 4 | offline: built-in capabilities, no schema validation, no collision check | cluster: real `.Capabilities`, live schema validation, collision check, `lookup` |
  | `helm install`, Helm 3 | needs the cluster: real `.Capabilities`, live schema validation, collision check; `lookup` empty | same plus `lookup` |
  | `helm upgrade`, both lines | needs the cluster: live schema validation, collision check; `lookup` empty | same plus `lookup` |

  For a render with no cluster at all, use `helm template` (or `helm lint`). Spell the mode out, since bare `--dry-run` is deprecated in Helm 4 (as is `helm template --validate`). Neither mode submits objects, so admission webhooks, policy engines, and quotas never run. For those, render and pipe: `helm template rel ./mychart -f prod.yaml | kubectl apply --dry-run=server -f -`.
- **Dry-run output contains rendered Secrets.** Add `--hide-secret` (3.15+) when the output goes to CI logs.
- **`-s/--show-only templates/x.yaml`** narrows rendering to one template so a single broken file isn't buried.
- **Offline rendering uses built-in capabilities**: the Kubernetes version the binary was compiled against and no CRD API groups, so resources guarded by `.Capabilities.APIVersions.Has` silently vanish from `helm template`. Pass the target: `--kube-version 1.34 --api-versions monitoring.coreos.com/v1` (`helm lint --kube-version` since 3.14).

**When a YAML parse error blocks all output**, comment out the suspect block with `#` and re-run `helm template --debug` — everything else renders so you can localize the fault, then re-enable and fix.

## Common render-time errors

| Symptom | Cause and fix |
|---------|---------------|
| `nil pointer evaluating interface {}.X` | Accessing a sub-key of an unset value. Guard with `{{- with .Values.a }}…{{- end }}`, `default`, or `hasKey`. |
| `did not find expected key` / `mapping values are not allowed` | Indentation wrong in output — almost always a missing `nindent`, or `template` used where `include \| nindent` was needed. |
| `wrong type for value` | A number was quoted or a string left unquoted; fix `quote`/`toString`. |
| `error calling include: template: no template "X"` | Helper name typo or not namespaced/defined; check `_helpers.tpl`. |
| `function "X" not defined` | The function is newer than the client: e.g. `toYamlPretty` needs 3.17+, `mustToYaml` needs Helm 4. Check `helm version` on every machine that renders the chart. |
| `[WARNING] Chart.yaml: failed to strictly parse … unknown field` (fails `lint --strict`) | Helm 4 parses `Chart.yaml` strictly; move custom keys under `annotations:`. |
| `unclosed action` / `unexpected "}" in operand` | Missing/extra `{{ end }}` or malformed action. |
| `execution error … required` | A `required` function fired — supply the value. |
| Output has stray blank lines | Whitespace control — use `{{-`/`-}}` and `nindent`. |

## Validate rendered manifests against the Kubernetes schema

`helm lint` checks chart conventions, not whether the output is valid Kubernetes. Render, then validate the manifests:

```bash
helm template rel ./mychart -f prod.yaml > /tmp/rendered.yaml
kubeconform -summary -strict /tmp/rendered.yaml      # validate against k8s + CRD schemas
yamllint /tmp/rendered.yaml                          # catch YAML lint issues
```

`kubeconform` (successor to `kubeval`) checks resources against the Kubernetes OpenAPI schema and can load CRD schemas; it's the right pre-deploy gate. The bundled `scripts/helm-chart-validate.sh` chains lint → template → yamllint/kubeconform when those tools are present.

## Runtime: debugging a release

```bash
helm status my-release -n my-ns                 # status + NOTES
helm history my-release -n my-ns                # revisions and their states
helm get manifest my-release -n my-ns           # what Helm actually applied (source of truth)
helm get values my-release -n my-ns -a          # computed values in effect
kubectl get events -n my-ns --sort-by=.lastTimestamp
kubectl describe deploy/<name> -n my-ns
kubectl logs deploy/<name> -n my-ns --all-containers --tail=100
```

Separate **release health** from **workload health**: `helm status` can say `deployed` while pods are `CrashLoopBackOff`. If the release deployed but the app is broken, pivot to `kubectl` on the rendered objects. `bash scripts/helm-release-debug.sh my-release -n my-ns` collects this in one pass.

### Apply, wait, and ownership failures

Most of these are new with Helm 4; check `helm version` before diagnosing.

| Symptom | Cause and fix |
|---------|---------------|
| `Apply failed with N conflict(s): conflict with "<manager>"` on upgrade | Helm 4 server-side apply: another field manager (an HPA, an operator, a past `kubectl edit`) owns a field the chart sets. Stop setting the field in the chart (e.g. `replicas` under an HPA), or re-run with `--force-conflicts` once Helm should own it. `helm get metadata` shows the release's `APPLY_METHOD`. |
| `invalid operation: cannot use server-side apply and force replace together` | Helm 4: `--force-replace` (or `--force`) on a release that uses server-side apply, which every release Helm 4 created does. Drop the flag, or add `--server-side=false` if a full replacement is really needed. |
| `--wait` / `--rollback-on-failure` times out on Helm 4 where Helm 3 passed | Bare `--wait` is now the kstatus `watcher`: it waits for every object, including custom resources, and needs `list`/`watch` RBAC on each kind. Find the object that never becomes ready (`kubectl get <kind> -o yaml`, read `status.conditions`), fix RBAC, or pass `--wait=legacy`. Use 4.1.3+; earlier kstatus waits could hang or fail early. |
| `… exists and cannot be imported into the current release: invalid ownership metadata` | The object exists without Helm's `app.kubernetes.io/managed-by: Helm` label and `meta.helm.sh/release-name`/`release-namespace` annotations, or belongs to another release. Adopt it with `--take-ownership` (3.17+) after confirming nothing else manages it; before 3.17, add the label and annotations by hand. |
| `helm uninstall` leaves objects behind, listed as "not owned by this release" | Helm 4.3.0+ deletes only objects whose ownership metadata still points at the release. Something relabelled them or another release adopted them; inspect before deleting by hand. |
| Rendered YAML from an `oci://` chart starts with `Pulled:` / `Digest:` | Helm 4.2.1–4.2.4 printed pull messages to stdout for `helm template`/`helm show`. Upgrade to 4.3.0. |
| A hook Job failed and the upgrade output says nothing useful | Annotate the hook `helm.sh/hook-output-log-policy: hook-failed` (3.18+) so Helm prints its Pod logs, or `kubectl logs job/<name>` before the delete policy removes it. |

### "My values aren't taking effect"

1. `helm get values my-release -n my-ns -a` — confirm what Helm actually computed.
2. Check precedence: `--set` overrides `-f`; later `-f` overrides earlier; `--set` *replaces* arrays.
3. On upgrade, check the reuse flag: a plain `helm upgrade --set x=y` drops every earlier override. Use `--reset-then-reuse-values` (3.14+) to keep them on top of the new chart's defaults; `--reuse-values` keeps them but renders against the old chart's defaults (table in `03-cli-and-release-lifecycle.md`).
4. Confirm the template actually *reads* the value (`helm template` and grep the output).
5. To remove a default rather than override it, set the key to `null` (subchart and empty-map cases fixed in 3.20.1 / 4.1.3).

## Recovering a stuck release

A release stuck in `pending-install`, `pending-upgrade`, or `uninstalling` usually means a previous Helm operation was interrupted (process killed, timeout, cluster blip) and never recorded a terminal state.

```bash
helm history my-release -n my-ns        # confirm the stuck/pending revision
```

Options, least-destructive first:

- **`helm rollback my-release <last-good-revision> -n my-ns`** — return to a known-good revision. Often clears a `pending-upgrade`. Helm 4.3.0+ can record why: `--description "revert bad config"`.
- **`helm upgrade ... --rollback-on-failure`** (Helm 4; `--atomic` on Helm 3) going forward so future failures self-recover.
- If rollback won't proceed, the release Secret may be wedged. Helm 3 and Helm 4 both keep release state in Secrets named `sh.helm.release.v1.<release>.v<rev>`:

  ```bash
  kubectl get secret -n my-ns -l owner=helm,name=my-release
  ```

  Deleting the *latest* pending revision Secret can unstick Helm, but **this is destructive metadata surgery** — confirm with the user, back up the Secret first, and prefer `rollback`. The `helm-mapkubeapis` plugin and `helm rollback` cover most cases without manual surgery.

## helm test for post-deploy validation

```bash
helm test my-release -n my-ns
```

Runs the chart's `templates/tests/` hook Pods against the live release. A good smoke-test gate after install/upgrade in CI.

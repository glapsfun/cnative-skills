---
name: helm
description: Expert guidance for Helm — the Kubernetes package manager. Use whenever the user creates, edits, reviews, or debugs a Helm chart or anything under a chart (Chart.yaml, values.yaml, values.schema.json, templates/*.yaml, _helpers.tpl, charts/, crds/); writes or fixes Go/Sprig template syntax ({{ }}, include, define, template, range, with, toYaml, nindent, indent, tpl, required, quote, default); runs the helm CLI (install, upgrade, rollback, uninstall, lint, template, package, dependency, repo, search, show, get, pull, status, history, test, plugin, registry); migrates from Helm 3 to Helm 4 (renamed flags like --atomic/--rollback-on-failure, server-side apply conflicts, --wait strategies, plugin signature verification); manages releases or values across environments; discovers or vendors existing charts from repositories, Artifact Hub, or OCI registries; or debugs failures like "helm template fails", "wrong indentation", "nil pointer evaluating interface", "release stuck in pending-upgrade", "values not taking effect", or rendered YAML that won't apply. Trigger on Helm chart files, helm command output, Go template errors, or Kubernetes packaging/release questions where Helm is the tool — even when the user doesn't say "Helm" but is clearly working inside a chart.
---

# Helm

Use this skill to work with Helm as the Kubernetes package manager: authoring and templating charts, driving the `helm` CLI, managing the release lifecycle, discovering and vendoring existing charts, and debugging chart-rendering and release failures.

Treat Helm behavior as **version-sensitive**. Helm 4 is the current major (skill verified against v4.3.0 and v3.22.0, 2026-09-28); Helm 3 is frozen at 3.22.x and receives security fixes only; Helm 2 (Tiller) is dead. Assume Helm 4 unless told otherwise, but expect many users and CI images still on Helm 3: several lifecycle flags were renamed in Helm 4 (`--atomic` → `--rollback-on-failure`, `--force` → `--force-replace`, which fails on server-side-apply releases), new installs use server-side apply, and `--wait` changed semantics. When a flag differs, give the Helm 4 form and name the Helm 3 one. Chart API version (`apiVersion: v2` works on both), Kubernetes version (which API groups exist), template function set, and chart dependency versions also drift. Verify against the user's actual `helm version`, cluster, and chart rather than trusting memorized syntax.

## First step

For anything beyond a trivial question, check the toolchain and target so your advice matches reality:

```bash
bash scripts/helm-version-check.sh
```

This reports the Helm client version (and whether it is the Helm 3 or Helm 4 line), the active Kubernetes context/version, installed Helm plugins (notably `helm-diff`), and whether supporting validators (`yamllint`, `kubeconform`) are available — which determines what you can actually run versus only recommend. Each Helm minor supports its compiled Kubernetes minor and the three before it (4.3.x and 3.22.x: Kubernetes 1.34–1.37); a cluster newer than that range is unsupported.

If the user gives a `helm version`, chart `apiVersion`, target Kubernetes version, rendered output, or command error, use that as the target context. If nothing is known, state the assumptions your answer uses and recommend verifying against the live environment.

## The two failure surfaces: render time vs runtime

Almost every Helm problem is one of two kinds, and confusing them wastes time:

- **Render-time** — the chart fails to produce valid YAML: template syntax errors, nil-pointer evaluations, wrong indentation, bad values. These are debugged **locally without a cluster** using `helm lint` and `helm template`. You never need a cluster to fix these (note that `helm upgrade --dry-run`, and `helm install --dry-run` on Helm 3, still connect to one).
- **Runtime** — the chart renders fine but the release misbehaves: install/upgrade fails, pods crash, a release is stuck in `pending-upgrade`, or values "don't take effect". These need live evidence: `helm status`, `helm history`, `helm get manifest/values`, and `kubectl`.

Identify which surface you're on first, then read the matching reference. See `references/04-debugging-and-validation.md`.

## Render the chart before believing anything about it

The cardinal rule of Helm work: **never reason about what a chart produces from the templates alone — render it and read the output.** Template logic, value precedence, and whitespace interact in ways that are far easier to see in the rendered manifest than to predict.

```bash
helm template my-release ./mychart              # render with defaults
helm template my-release ./mychart -f prod.yaml --set image.tag=1.2.3   # with the actual values
helm lint ./mychart --strict                    # catch best-practice and syntax issues
helm install my-release ./mychart --dry-run=server --debug   # render + validate against the live API
```

What `--dry-run=server` (Helm 3.13+) adds over `--dry-run=client` is mainly a working `lookup`. `helm upgrade` dry-runs on both lines, and `helm install` dry-runs on Helm 3, connect to the cluster in either mode (real `.Capabilities`, schema validation against the live API, a check for existing objects the release would collide with). Only Helm 4 `helm install --dry-run=client` stays offline. Write the mode explicitly: bare `--dry-run` is deprecated in Helm 4. Neither mode submits objects, so admission webhooks and quotas are not exercised. Dry-run output includes Secrets; add `--hide-secret` (3.15+) when it lands in CI logs. Use the bundled validator to chain lint + render + schema checks in one read-only pass:

```bash
bash scripts/helm-chart-validate.sh ./mychart
bash scripts/helm-chart-validate.sh ./mychart -f values-prod.yaml
```

## Task routing

Read the reference that matches the task — each is a focused deep-dive so you load only what you need:

- **Chart structure, `Chart.yaml`, `values.yaml`, `values.schema.json`, `helm create`, dependencies/subcharts, library charts, hooks, packaging** → `references/01-chart-anatomy-and-authoring.md`
- **Go template + Sprig syntax: built-in objects (`.Release`/`.Chart`/`.Values`/`.Files`/`.Capabilities`), pipelines, functions, `define`/`include`/`template`, `_helpers.tpl`, flow control (`if`/`with`/`range`), scope/`$`, variables, whitespace control, `toYaml`/`nindent`/`tpl`/`required`** → `references/02-templating-go-and-sprig.md`
- **The `helm` CLI and release lifecycle: install/upgrade/rollback/uninstall, values precedence and `--reuse-values`/`--reset-then-reuse-values`, `--rollback-on-failure`/`--atomic`, `--wait`, `--take-ownership`, `history`/`status`/`get`, `helm test`, helm-diff, OCI registries** → `references/03-cli-and-release-lifecycle.md`
- **Helm 4 vs Helm 3: renamed and removed flags, server-side apply and `--force-conflicts`, `--wait` strategies (kstatus `watcher`, `legacy`), post-renderer plugins, plugin signature verification, migrating CI, minimum safe Helm 4 patch** → `references/03-cli-and-release-lifecycle.md` § "Helm 4 vs Helm 3"
- **Debugging and validation: render-time vs runtime, common template errors, `--dry-run`/`--debug`, `get manifest`, stuck releases, Helm 4 runtime failures (field conflicts, wait timeouts, ownership), `yamllint`/`kubeconform`** → `references/04-debugging-and-validation.md`
- **Chart best practices: values naming/structure, labels and annotations, resources/probes/securityContext, RBAC, CRDs, image handling** → `references/05-best-practices.md`
- **Discovering and vendoring charts: `helm search hub`/`repo`, `repo add/update`, `show`, `pull`, Artifact Hub, OCI** → `references/06-discovery-and-repos.md`
- **Authoritative docs (helm.sh for Helm 4, helm.sh/docs/v3/ for Helm 3, Sprig, Go text/template, Artifact Hub)** → run `bash scripts/helm-doc-discover.sh`

## Core operating rules

These apply to nearly all Helm work; the references explain the why in depth.

**Render and inspect, don't guess.** Before claiming a chart does X, run `helm template` (or `helm get manifest` for an installed release) and read the actual YAML. Indentation and value precedence bugs are invisible in the template source.

**Get indentation right with `nindent`, and prefer `include` over `template`.** Helm output is YAML, where indentation is structure. Use `{{ include "chart.labels" . | nindent 4 }}` — `include` can pipe into `nindent`/`indent` (which set absolute/relative indentation and prepend a newline), while the `template` action cannot pipe at all. Embed value subtrees with `{{- toYaml .Values.resources | nindent 2 }}`.

**Quote strings; be careful with numbers.** Unquoted values get YAML type coercion — `1.10` becomes `1.1`, `yes`/`no` become booleans, a leading-zero version mangles. Use `| quote` for strings and `| toString`/explicit quoting for values that must stay strings (image tags, ports-as-strings).

**Namespace your template names.** Define helpers as `{{ define "mychart.fullname" }}`, never bare `fullname` — template names are global and collide across subcharts. `helm create` scaffolds this correctly; follow its convention.

**Mind values precedence.** Later sources win, in this order: chart `values.yaml` → parent chart values → `-f/--values` files (left to right) → `--set`/`--set-string`/`--set-file`. `--set` merges into maps but **replaces entire arrays**, a frequent "my override didn't work" cause. On `helm upgrade`, passing any `-f`/`--set` without a reuse flag **drops the previous release's overrides**; use `--reset-then-reuse-values` (3.14+) to keep them, or keep all overrides in committed values files.

**Make destructive lifecycle operations safe.** Prefer `--rollback-on-failure` (Helm 4; `--atomic` on Helm 3) on `install`/`upgrade` so a failed rollout rolls back instead of leaving a wedged release. Use `helm diff upgrade` (helm-diff plugin) to preview changes before applying. Treat `helm rollback`, `uninstall`, `--force-replace` (`--force` on Helm 3), `--force-conflicts`, and `--take-ownership` as state-changing — confirm intent and check `helm history` first.

**Don't hand-edit live cluster objects a chart manages.** Helm tracks release state; manual `kubectl edit` of chart-owned resources causes drift and surprises on the next `helm upgrade`. With Helm 4 server-side apply the surprise is a hard field-manager conflict that fails the upgrade. Change the chart/values and upgrade instead.

## Creating a new chart

Start from the scaffold, then strip it down — don't hand-write boilerplate:

```bash
helm create mychart        # generates a best-practice chart skeleton
```

`helm create` gives you correctly namespaced `_helpers.tpl`, a deployment/service/ingress/serviceaccount/HPA set (plus a Gateway API `httproute.yaml`, disabled by default, since 3.19), sane labels, and a `values.yaml` wired to them. Delete what you don't need rather than authoring from a blank file — the scaffold already embodies many of the best practices in `references/05-best-practices.md`. Then add a `values.schema.json` to validate inputs, and run `scripts/helm-chart-validate.sh` before declaring it done. See `references/01-chart-anatomy-and-authoring.md`.

## Reviewing or hardening an existing chart

Work in this order — it surfaces the highest-severity issues first:

1. **Render it** with realistic values (`helm template … -f prod.yaml`) and read the output; run `scripts/helm-chart-validate.sh` (lint --strict + render + schema/kubeconform when available).
2. **Check `Chart.yaml`**: correct `apiVersion: v2`, sane SemVer `version`/`appVersion`, declared `dependencies` with pinned versions.
3. **Scan templates for the classic footguns**: missing `nindent`/wrong indentation, unquoted strings, bare (non-namespaced) template names, `.Values.x.y` access without nil-guarding (`nil pointer evaluating interface {}`), hardcoded namespaces/values that should be configurable, and secrets rendered in plain ConfigMaps.
4. **Check values**: camelCase keys, flat-over-nested where reasonable, documented, and a `values.schema.json` enforcing required/typed inputs.
5. **Check operational hygiene**: resource requests/limits, liveness/readiness probes, `securityContext`, image tag not `latest`, labels/annotations following convention.

Explain *why* each change matters rather than rewriting silently, and prefer the smallest change that removes the hazard unless the user asked for a rewrite.

## Debugging a failing release

Reproduce and gather evidence before theorizing:

```bash
helm status my-release -n my-ns                 # current state + notes
helm history my-release -n my-ns                # revisions; spot a failed/ superseded upgrade
helm get manifest my-release -n my-ns           # what Helm actually applied
helm get values my-release -n my-ns -a          # the values in effect (computed)
kubectl get events -n my-ns --sort-by=.lastTimestamp
```

For a release stuck in `pending-install`/`pending-upgrade` (often a crashed/interrupted operation), see the recovery steps in `references/04-debugging-and-validation.md`. Use the bundled helper to collect this in one pass:

```bash
bash scripts/helm-release-debug.sh my-release -n my-ns
```

# cnative-skills

[![CI](https://github.com/glapsfun/cnative-slills/actions/workflows/ci.yml/badge.svg)](https://github.com/glapsfun/cnative-slills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Agentic skills for cloud-native tools, distributed as a [Claude Code plugin marketplace](https://docs.anthropic.com/en/docs/claude-code).

## Plugins

| Plugin | Description |
| :--- | :--- |
| `kubernetes-operator` | Expert Kubernetes assistant — kubectl commands and scripting, writing/reviewing manifests, Helm charts, GitOps (Flux, Argo CD, kustomize), security hardening, debugging playbooks (CrashLoopBackOff, Pending pods, ImagePullBackOff, OOMKilled, and more), and cluster operations. |
| `kagent` | Expert guide for [kagent](https://kagent.dev) — the CNCF framework for running AI agents on Kubernetes: CLI, Agent/ModelConfig/RemoteMCPServer CRDs, MCP tools, A2A subagents, human-in-the-loop approval, long-term memory, IDE integration, Helm/OIDC/observability, and troubleshooting. Derived from and extending the upstream [kagent skill](https://github.com/kagent-dev/kagent/tree/main/.claude/skills/kagent) (Apache-2.0). |
| `kgateway` | Expert guide for [kgateway](https://kgateway.dev) — the CNCF Kubernetes Gateway API implementation powered by Envoy (formerly Gloo by Solo.io): installation, Gateway/HTTPRoute/TCPRoute setup, traffic management (splitting, delegation, transformations), security (TLS/mTLS, JWT, ext-auth, rate limiting, CORS, IP ACL), resiliency (retries, timeouts, circuit breakers, fault injection), Istio integration, observability, debugging, and upgrade procedures including v2.3 migration. |
| `fluxcd` | Expert guide for [Flux CD](https://fluxcd.io/flux/) — Kubernetes GitOps install/bootstrap, repository structure, Flux source/Kustomization/Helm/notification resources, SOPS and RBAC security, schema validation, operations, upgrades, and troubleshooting. |

---

## Installation

### Method 1 — Claude Code (slash commands, recommended)

This is the standard way to install plugins in Claude Code or any environment that supports the `/plugin` slash command (including the Claude desktop app and VS Code/JetBrains extensions).

**Step 1 — Add the marketplace** (one-time per machine):

```
/plugin marketplace add glapsfun/cnative-slills
```

This registers the marketplace under the alias **`cnative-skills`** (from the `name` field in `.claude-plugin/marketplace.json` — note the alias differs from the GitHub repo slug `cnative-slills`).

**Step 2 — Install a plugin**:

```
/plugin install kubernetes-operator@cnative-skills
```

Replace `kubernetes-operator` with any plugin name from the table above.

**To update all plugins from this marketplace** after new versions are published:

```
/plugin marketplace update cnative-skills
```

**To remove a plugin**:

```
/plugin remove kubernetes-operator
```

---

### Method 2 — Claude Code CLI (non-interactive)

If you have `claude` on your `PATH` (or use `npx @anthropic-ai/claude-code` to run it without a global install), the `plugin` subcommand works non-interactively:

```bash
claude plugin marketplace add glapsfun/cnative-slills
claude plugin install kubernetes-operator@cnative-skills
```

With npx (no prior global install required):

```bash
npx @anthropic-ai/claude-code plugin marketplace add glapsfun/cnative-slills
npx @anthropic-ai/claude-code plugin install kubernetes-operator@cnative-skills
```

> Note: `claude "/plugin ..."` (with the slash command as a quoted string) passes that string as a model prompt, not as a plugin command — use `claude plugin ...` (no leading slash) for non-interactive use.

---

### Method 3 — Codex

Add the repository as a Codex plugin marketplace and install a plugin:

```
/plugin marketplace add glapsfun/cnative-slills
/plugin install kubernetes-operator@cnative-skills
```

Codex marketplace metadata lives in `.agents/plugins/marketplace.json`; plugin manifests live in `plugins/<name>/.codex-plugin/plugin.json`.

---

### Method 4 — Local / development install

Use this method when iterating on a local clone of this repository before publishing.

```bash
git clone https://github.com/glapsfun/cnative-slills.git
cd cnative-slills
```

Then, inside Claude Code, substitute the actual path to your clone:

```
/plugin marketplace add /path/to/cnative-slills
/plugin install kubernetes-operator@cnative-skills
```

The path must point to the repo root (the directory containing `.claude-plugin/marketplace.json`). Using an absolute path avoids ambiguity. A relative path like `./cnative-slills` only works if your working directory is the parent of the clone.

---

### Install all plugins at once

After adding the marketplace (step 1 of any method above), install all plugins:

```
/plugin install kubernetes-operator@cnative-skills
/plugin install kagent@cnative-skills
/plugin install kgateway@cnative-skills
/plugin install fluxcd@cnative-skills
```

---

## Repository layout

```
.claude-plugin/
  marketplace.json                  ← Claude Code marketplace catalog
.agents/plugins/
  marketplace.json                  ← Codex marketplace catalog
.ci/
  validate-structure.sh             ← plugin structure contract
  validate-marketplace-sync.sh      ← catalog vs directory consistency
  validate-json.sh                  ← JSON validity
  validate-markdown-internal-links.sh
  validate-shell-syntax.sh
.github/workflows/
  ci.yml                            ← GitHub Actions (runs all .ci/ scripts)
plugins/
  kubernetes-operator/
    .claude-plugin/plugin.json      ← Claude Code plugin manifest
    .codex-plugin/plugin.json       ← Codex plugin manifest
    skills/kubernetes-operator/
      SKILL.md                      ← main skill content
      agents/                       ← agent definitions
      evals/                        ← evaluation scenarios
      references/                   ← reference docs
      scripts/                      ← utility scripts
  kagent/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/kagent/
      SKILL.md
      agents/
      evals/
      references/
  kgateway/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/kgateway/
      SKILL.md
      evals/
      references/
  fluxcd/
    .claude-plugin/plugin.json
    .codex-plugin/plugin.json
    skills/fluxcd/
      SKILL.md
      agents/
      evals/
      references/
      scripts/
```

---

## Development

### Adding a new plugin

1. Create `plugins/<name>/` with the structure above.
2. Add `.claude-plugin/plugin.json` (Claude Code manifest) and `.codex-plugin/plugin.json` (Codex manifest).
3. Write the skill in `plugins/<name>/skills/<name>/SKILL.md`.
4. Register the plugin in both `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`.
5. Add an entry to the **Plugins** table in this README.

### Bumping a version

Increment `version` in both manifest files — users receive updates only when the version string changes:

- `plugins/<name>/.claude-plugin/plugin.json` — Claude Code
- `plugins/<name>/.codex-plugin/plugin.json` — Codex

### Running CI checks locally

```bash
bash .ci/validate-structure.sh
bash .ci/validate-marketplace-sync.sh
bash .ci/validate-json.sh
bash .ci/validate-markdown-internal-links.sh
bash .ci/validate-shell-syntax.sh
```

---

## CI

GitHub Actions runs on every push and pull request to `main` and enforces:

- Plugin structure contract (`plugins/<name>/.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`, and optional subdirectories)
- Marketplace and plugin consistency (catalog entries vs tracked plugin directories and manifests)
- JSON validity
- Internal Markdown link/reference integrity
- Shell script syntax (`bash -n`)

---

## License

[MIT](LICENSE)

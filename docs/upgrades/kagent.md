---
plugin: kagent
upstream_name: kagent
version_source: github-release
upstream_repo: kagent-dev/kagent
upstream_url:
upstream_key:
extra_repos: [kagent-dev/kmcp]
version_match: exact
verified_version: unknown
verified_date: 2026-06-28
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# kagent — upgrade memo

Ledger entry created 2026-09-14. Pre-1.0 project with fast CRD/Helm drift. The skill is derived from the upstream `.claude/skills/kagent` skill — diff against it every run. Content mentions v0.7 features; era implied ~v0.9. `verified_date` is the plugin's last content commit (proxy) — no verification run yet.

## Sources

- Releases: <https://github.com/kagent-dev/kagent/releases>
- Docs: <https://kagent.dev/docs>
- Upstream skill this plugin derives from: <https://github.com/kagent-dev/kagent/tree/main/.claude/skills/kagent>
- Tools catalog: <https://kagent.dev/tools>
- Agents catalog: <https://kagent.dev/agents>
- KMCP (MCPServer CRD): <https://github.com/kagent-dev/kmcp>

## Skill map

- `SKILL.md` — 168 lines
- `references/agent-configuration.md` — Agent Configuration Reference
- `references/cli-reference.md` — kagent CLI Overview
- `references/hitl-and-memory.md` — Human-in-the-Loop & Long-Term Memory
- `references/mcp-ide-setup.md` — Exposing kagent Agents as MCP Tools in Your IDE
- `references/operations.md` — Operations: Helm, Auth, Observability, Architecture
- `references/providers.md` — LLM Provider Configuration
- `references/troubleshooting.md` — Troubleshooting kagent
- `evals/evals.json` — 16 evals

## Watch list

- `references/agent-configuration.md` — CRD kinds (`Agent`, `ModelConfig`, `RemoteMCPServer`, `MCPServer`) and apiVersions.
- `references/providers.md` — supported model providers and their `ModelConfig` keys.
- `references/cli-reference.md` — `kagent` CLI subcommands.
- `references/operations.md` — Helm values, OIDC, observability keys.
- No version-check script; add one when the baseline is established.

## Open items

- 2026-09-14: ledger created; establish `verified_version` on the first update run.

## Upgrade log

(no runs yet)

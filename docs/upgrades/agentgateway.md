---
plugin: agentgateway
upstream_name: agentgateway
version_source: github-release
upstream_repo: agentgateway/agentgateway
upstream_url:
upstream_key:
extra_repos: []
version_match: exact
verified_version: v1.3.1
verified_date: 2026-07-15
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# agentgateway — upgrade memo

Ledger entry created 2026-09-14. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Releases: <https://github.com/agentgateway/agentgateway/releases>
- Docs (standalone): <https://agentgateway.dev/docs/standalone/latest/>
- Docs (Kubernetes / kgateway integration): <https://agentgateway.dev/docs/kubernetes/latest/>
- Config schema reference: <https://agentgateway.dev/docs/standalone/latest/reference/configuration/schema/>
- Examples: <https://github.com/agentgateway/agentgateway/tree/main/examples>
- Design docs: <https://github.com/agentgateway/agentgateway/tree/main/design>

## Skill map

- `SKILL.md` — 249 lines
- `references/config-model.md` — agentgateway Config Model Reference
- `references/installation.md` — agentgateway Installation Reference
- `references/llm-routing.md` — agentgateway LLM / AI Gateway Reference
- `references/mcp.md` — agentgateway MCP Reference
- `references/observability.md` — agentgateway Observability Reference
- `references/security.md` — agentgateway Security Reference
- `references/traffic-and-a2a.md` — agentgateway Traffic Management & A2A Reference
- `references/troubleshooting.md` — agentgateway Troubleshooting Reference
- `scripts/agentgateway-doc-discover.sh` — Lists design docs, example configs, and schema file paths from the official
- `scripts/agentgateway-version-check.sh` — Reports the latest upstream agentgateway release next to the skill's
- `evals/evals.json` — 8 evals

## Watch list

- `scripts/agentgateway-version-check.sh` — `BASELINE` default (`v1.3.1`); update with every verified bump.
- `references/installation.md` — pinned binary/Helm versions and the `binds`/`gateways` config-schema shape (script comment flags a schema migration risk).
- `references/llm-routing.md` — provider list and virtual-model routing fields.
- `references/config-model.md` — top-level config keys; compare against the schema page above.
- `SKILL.md` — CRD names `AgentgatewayBackend` / `AgentgatewayPolicy` and their apiVersion.

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

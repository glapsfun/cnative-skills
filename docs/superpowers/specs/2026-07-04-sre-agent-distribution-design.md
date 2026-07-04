# sre-agent cross-agent distribution — design

Date: 2026-07-04
Status: approved

## Problem

The sre-agent plugin was Claude Code-shaped: the `/sre-agent` command and the
five investigator subagents live at plugin level (`commands/`, `agents/`),
which the Agent Skills standard (`npx skills`) does not install. Every
non-Claude agent received a skill whose Phase 3 degraded to a single triage
script.

## Decision

**Portable-core skill + generated per-target accelerators.**

Targets (user-selected): Codex CLI, Gemini CLI, GitHub Copilot CLI (plus
Claude Code, unchanged).

1. **Portable core.** The skill runs the full 6-phase investigation without
   subagents. The five investigator playbooks live in
   `skills/sre-agent/references/investigators/{k8s,metrics,logs,changes,traces}.md`
   — the single source of truth, shipped with the skill everywhere. SKILL.md
   Phase 3 has two paths: Path A dispatches named subagents concurrently when
   the host provides them; Path B executes the playbooks inline, sequentially
   — same evidence, same findings-block format.
2. **Generated artifacts.** `scripts/gen-sre-agent-artifacts.sh` derives from
   the playbook sources, byte-identical bodies, committed and CI-enforced by
   `scripts/checks/sre-agent-artifacts.sh` (wired into `validate.sh`
   FAST_CHECKS):
   - `plugins/sre-agent/agents/*.md` — Claude Code subagents (frontmatter
     from source metadata: `name`, `description`, `claude-tools`,
     `claude-file`).
   - `plugins/sre-agent/skills/sre-agent/agents/codex/*.toml` — Codex
     subagents (`name`, `description`, `developer_instructions` with the
     playbook embedded; no runtime path resolution). Bundled inside the skill
     so `npx skills` ships them; installed by the bundled
     `scripts/install-codex-agents.sh` into `${CODEX_HOME:-~/.codex}/agents/`
     (or `.codex/agents/` with `--project`).
3. **Gemini CLI / Copilot CLI** get the portable core via the standard skill
   install; Copilot has no user-defined subagents, Gemini's are
   semi-documented — both run Path B at full fidelity.

## Rejected alternatives

- **Thin-wrapper agents** reading playbooks from the plugin at runtime:
  subagents run in the user's project directory; `${CLAUDE_PLUGIN_ROOT}` is
  not documented to expand in agent bodies — a path-resolution failure would
  break the whole parallel dispatch.
- **Max parity per target** (native subagents for Gemini too): Gemini's TOML
  agents are semi-official; not worth a third generated dialect.
- **Skill-only everywhere** (status quo): non-Claude users permanently get a
  weaker investigation.

## Consequences

- Editing an investigator means editing
  `references/investigators/*.md` and running the generator; CI fails on
  drift.
- Codex TOMLs freeze the playbook at generation time; users re-run
  `install-codex-agents.sh` after skill updates (noted in READMEs).
- Plugin version 0.3.0 (both manifests).

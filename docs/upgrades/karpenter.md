---
plugin: karpenter
upstream_name: Karpenter
version_source: github-release
upstream_repo: aws/karpenter-provider-aws
upstream_url:
upstream_key:
extra_repos: [kubernetes-sigs/karpenter]
version_match: exact
verified_version: v1.13.0
verified_date: 2026-07-02
last_upgrade: never
plugin_version: 1.0.0
check_interval_days: 90
---

# karpenter — upgrade memo

Ledger entry created 2026-09-14. `verified_date` is the date the baseline stated in the plugin was collected.

## Sources

- Releases (AWS provider): <https://github.com/aws/karpenter-provider-aws/releases>
- Releases (core): <https://github.com/kubernetes-sigs/karpenter/releases>
- Docs: <https://karpenter.sh/docs/>
- Upgrade guide: <https://karpenter.sh/docs/upgrading/upgrade-guide/>
- Compatibility matrix: <https://karpenter.sh/docs/upgrading/compatibility/>
- Design docs (RFCs): <https://github.com/kubernetes-sigs/karpenter/tree/main/designs>
- EKS Auto Mode docs: <https://docs.aws.amazon.com/eks/latest/userguide/automode.html>
- EKS best practices: <https://docs.aws.amazon.com/eks/latest/best-practices/karpenter.html>

## Skill map

- `SKILL.md` — 167 lines
- `references/auto-mode.md` — EKS Auto Mode (built-in Karpenter)
- `references/disruption.md` — Disruption: consolidation, drift, expiration, budgets
- `references/ec2nodeclass.md` — EC2NodeClass reference (`karpenter.k8s.aws/v1`, self-hosted only)
- `references/nodepools.md` — NodePool reference (`karpenter.sh/v1`)
- `references/official-sources.md` — Official Sources
- `references/operations.md` — Operations: install, IAM, spot infra, upgrades, observability, cost patterns
- `references/troubleshooting.md` — Troubleshooting
- `scripts/karpenter-version-check.sh` — Reports the latest upstream Karpenter AWS provider release next to the
- `evals/evals.json` — 3 evals

## Watch list

- `SKILL.md` — "skill baseline 2026-07-02: upstream v1.13.0, K8s ≤ 1.36".
- `references/official-sources.md` — "Baseline collected … v1.13.0" and the design-doc list with predicted versions (capacity buffers ~v1.14, balanced consolidation) — confirm when they ship.
- `scripts/karpenter-version-check.sh` — `BASELINE` default (`v1.13.0`).
- README plugin row — "verified against upstream v1.13".
- `references/ec2nodeclass.md` / `references/nodepools.md` — CRD fields promoted or deprecated.

## Open items

- 2026-09-14: ledger created; no upgrade run yet.

## Upgrade log

(no runs yet)

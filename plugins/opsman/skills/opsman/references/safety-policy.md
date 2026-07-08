# Opsman Safety Policy

## Risk classes

| Class | Meaning | Handling |
| --- | --- | --- |
| R0 | Read-only discovery | automatic |
| R1 | Local generated artifacts (`.opsman/`) | automatic |
| R2 | Source/manifest modification | automatic in worktree, must validate |
| R3 | External non-production side effect | explicit policy or user approval |
| R4 | Production or destructive action | always explicit user approval |

Milestone 1 only performs R0–R1 actions (plus appending one line to the
target repo's `.gitignore`). Plan-step risk declaration and command
policy enforcement arrive in milestone 3.

## Deny patterns (escalate to R4 regardless of declared risk)

`kubectl apply`, `kubectl delete`, `terraform apply`, `pulumi up`,
`git push --force`, credential rotation, IAM policy changes, resource
deletion in any live environment.

## Approval flow

R3/R4 → event `HumanApprovalRequired` → state `WAITING_APPROVAL`. The
agent asks the user in conversation; the reply is recorded as an
`ApprovalGranted` event whose payload states who approved what and when.
The audit trail lives in `events.jsonl` and survives tool switches.

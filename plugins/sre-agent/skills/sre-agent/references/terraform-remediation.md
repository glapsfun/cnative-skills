# Terraform Remediation

Read during Phase 4 (locating the resource) and Phase 5/6 (constructing and
applying the fix) whenever evidence shows the remediation target is
Terraform-managed — the IaC-ownership check already run in
`investigators/eks.md`/`investigators/gke.md` (or `references/remediation.md`'s
"AWS/EKS infrastructure changes"/"GCP/GKE infrastructure changes" sections)
found `terraform`-style tags/labels rather than CDK, eksctl, or Config
Connector ownership. Safety rule 5 still applies unchanged: a direct
`aws`/`gcloud`/console mutation to a Terraform-managed resource needs
explicit acknowledgment that the next `plan`/`apply` will revert it.

## 1. Locate the resource in the IaC repo

Prefer state over grep — it's authoritative and immune to naming drift:

```bash
terraform -chdir=<tf-dir> state list | grep -i <resource-name-or-type>
terraform -chdir=<tf-dir> state show <resource-address>
```

If state access isn't available (no backend credentials, or the agent only
has read access to the repo, not the backend), fall back to grep across the
module for the identifier evidence already produced — the IAM role name
from an `eks.amazonaws.com/role-arn` annotation, the node group name, the
GSA email from an `iam.gke.io/gcp-service-account` annotation, or a
`terraform`-style tag value:

```bash
grep -rn '<identifier>' <tf-dir> --include='*.tf'
```

Before proposing an edit, understand the module layout: is this a root
module or does the matched resource live inside a child module (`module
"..." { source = ... }`)? Is the environment split by Terraform workspace
(`terraform workspace list`) or by directory (`environments/prod/`,
`environments/staging/`)? Editing the wrong workspace/directory produces a
plan that looks clean locally but never reaches the resource that's
actually broken. Confirm the backend (`terraform { backend "s3" { ... } }`
or equivalent) matches the account/project the evidence came from — never
assume the directory you're standing in is the one that owns the live
resource.

## 2. Read `terraform plan` safely

Never trust a stale plan file — always regenerate before reasoning about
impact:

```bash
terraform -chdir=<tf-dir> plan -input=false -no-color
```

For each changed resource, read the **reason**, not just the action:
in-place `~ update` is usually safe; `-/+ destroy and then create replacement`
(a "replace") means some attribute you changed is immutable for that
resource type — Terraform prints which attribute forced it
(`# forces replacement` next to the attribute). A replace on a stateful
resource (a node group, a database, anything with an identity workloads
depend on) is a different risk class than a replace on a stateless one; call
this out explicitly in the option's Risk field, don't let "it's just a
Terraform change" hide a destroy.

`-target=<address>` narrows a plan/apply to one resource and is tempting
when you only want to touch the thing you diagnosed — but it hides
dependency-graph effects: a resource the target depends on (or that depends
on it) can drift out of sync with configuration without appearing in the
narrowed plan. Use it only as a last resort under time pressure, and say so
explicitly in the option's Risk field; the default is always a full plan.

## 3. Construct the fix

Show the exact HCL diff in the option's Steps section — not a description
of what to change, the actual before/after. Match the module's existing
conventions: reuse its variables, follow its naming, don't hand-roll a new
resource block when an existing variable already parameterizes the value
you need to change. If the same fix is needed in more than one
environment/workspace, say so and show the diff for each — don't fix prod
silently while staging drifts.

## 4. Classify the plan before it goes in front of the user

Run the plan through the classifier instead of reading raw plan output for
the risk call — this is the same "verify mechanically, don't trust your own
reading" principle `scripts/sre-snapshot.sh` applies to Phase 3:

```bash
scripts/terraform-plan-check.sh <tf-dir> [terraform plan args...]
```

It prints a count of `no-op`/`create`/`update`/`delete`/`delete,create`
(replace) changes and lists every resource address involved in a delete or
replace, exiting `1` when any are present. Fold its output into the
option's Risk field and the ledger — a plan with zero delete/replace
entries supports Low/Medium risk; any delete or replace bumps the option to
at least Medium and usually High (per `remediation.md`'s risk
classification), and the exact addresses affected belong in the ledger's
evidence, not just a summary sentence.

## 5. Apply and rollback

Apply only after approval, and only the exact plan already classified and
shown — never re-plan-and-apply blind, since state may have moved between
the two:

```bash
terraform -chdir=<tf-dir> apply -input=false -no-color <the same plan file, or re-run plan+apply back to back with no intervening change>
```

Rollback is a Git operation, not a Terraform one: revert the HCL commit and
re-apply, the same way `references/remediation.md`'s GitOps paths revert
through a commit rather than a manual edit. Verify the rollback the same
way the original fix was verified — a clean `terraform plan` afterward
(zero diff against the reverted configuration) plus the expected-behavior
criteria from Phase 4.

## 6. State surgery is its own approval gate

`terraform state rm`, `terraform state mv`, `terraform import`, and
`terraform taint`/`untaint` change what Terraform believes about reality
without changing reality itself (or vice versa for `import`) — they are
mutating-class actions in their own right, never a silent step inside a
"fix." If evidence points at state/config divergence that needs one of
these to resolve, propose it as its own remediation option with its own
risk, steps, and rollback (per `remediation.md`'s option template) — do not
fold it into an unrelated option's Steps section.

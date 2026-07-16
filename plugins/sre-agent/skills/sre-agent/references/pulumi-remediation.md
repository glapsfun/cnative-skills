# Pulumi Remediation

Read during Phase 4 (locating the resource) and Phase 5/6 (constructing and
applying the fix) whenever evidence shows the remediation target is
Pulumi-managed — the IaC-ownership check already run in
`investigators/eks.md`/`investigators/gke.md` (or `references/remediation.md`'s
"AWS/EKS infrastructure changes"/"GCP/GKE infrastructure changes" sections)
found `pulumi:project`/`pulumi:stack` tags or cloud-provider tags the
program itself sets, rather than Terraform, CDK, eksctl, or Config
Connector ownership. Safety rule 5 still applies unchanged: a direct
`aws`/`gcloud`/console mutation to a Pulumi-managed resource needs explicit
acknowledgment that the next `preview`/`up` will revert it.

## 1. Locate the resource in the stack

List and select the stack that owns the resource, then inspect its state:

```bash
pulumi -C <stack-dir> stack ls
pulumi -C <stack-dir> stack select <stack>
pulumi -C <stack-dir> stack export | jq '.deployment.resources[] | select(.urn | test("<identifier>"))'
```

Never run `pulumi stack select` yourself without confirming it's the right
one — a wrong stack looks clean (empty preview) without ever reaching the
resource that's actually broken, the same trap as a Terraform workspace
mismatch. If state access isn't available, fall back to grep across the
program for the identifier evidence already produced — the IAM role/service
account name, node group/pool name, or a `pulumi:project`/`pulumi:stack`
tag value:

```bash
grep -rn '<identifier>' <stack-dir> --include='*.ts' --include='*.py' --include='*.go' --include='*.cs' --include='*.yaml'
```

Pulumi programs can be TypeScript/JavaScript, Python, Go, C#/.NET, Java, or
YAML — check `Pulumi.yaml`'s `runtime:` field before assuming a language.
Confirm the backend (`pulumi login <s3://...|azblob://...|gs://...|
https://api.pulumi.com>`) matches the account/project the evidence came
from — never assume the directory you're standing in points at the backend
that owns the live resource.

## 2. Read `pulumi preview` safely

Never trust a stale preview — always regenerate before reasoning about
impact:

```bash
pulumi -C <stack-dir> preview
```

For each changed resource, read the **op**, not just whether something
changed: `update` is usually safe; `replace` (or its detailed-diff
sub-steps `create-replacement`/`delete-replaced`) means some property is
immutable for that resource type (Pulumi's `ForceNew` behavior) — Pulumi
prints which property forced it. A replace on a stateful resource (a node
pool, a database, anything with an identity workloads depend on) is a
different risk class than a replace on a stateless one; call this out
explicitly in the option's Risk field, don't let "it's just a Pulumi
change" hide a destroy.

`--target=<urn>` narrows a preview/update to one resource and is tempting
when you only want to touch the thing you diagnosed — but it hides
dependency-graph effects the same way Terraform's `-target` does: a
resource the target depends on (or that depends on it) can drift out of
sync with the program without appearing in the narrowed preview. Use it
only as a last resort under time pressure, and say so explicitly in the
option's Risk field; the default is always a full preview.

## 3. Construct the fix

Show the exact diff in the option's Steps section — not a description of
what to change, the actual before/after, in whichever language the
program is written in. Match its existing conventions: reuse its
`pulumi.Config` values, follow its naming and resource-organization
patterns, don't hand-roll a new resource when an existing config value
already parameterizes what you need to change. If the same fix is needed
in more than one stack (dev/staging/prod), say so and show the diff for
each — don't fix prod silently while staging drifts.

## 4. Classify the plan before it goes in front of the user

Run the preview through the classifier instead of reading raw preview
output for the risk call — the same "verify mechanically, don't trust your
own reading" principle `scripts/sre-snapshot.sh` applies to Phase 3 and
`scripts/terraform-plan-check.sh` applies to Terraform remediation:

```bash
scripts/pulumi-preview-check.sh <stack-dir> [pulumi preview args...]
```

It reads the preview JSON's own `changeSummary` object for the op-count
summary (same/create/update/delete/replace/create-replacement/
delete-replaced) and lists every URN involved in a delete or replace,
exiting `1` when any are present. Fold its output into the option's Risk
field and the ledger — a preview with zero delete/replace entries supports
Low/Medium risk; any delete or replace bumps the option to at least Medium
and usually High (per `remediation.md`'s risk classification), and the
exact URNs affected belong in the ledger's evidence, not just a summary
sentence.

## 5. Apply and rollback

Apply only after approval, and only the exact change already classified
and shown — never re-preview-and-apply blind, since state may have moved
between the two:

```bash
pulumi -C <stack-dir> up
```

Rollback is a Git operation, not a Pulumi one: revert the program commit
and re-run `pulumi up`, the same way `references/remediation.md`'s GitOps
paths revert through a commit rather than a manual edit. Verify the
rollback the same way the original fix was verified — a clean
`pulumi preview` afterward (zero diff against the reverted program) plus
the expected-behavior criteria from Phase 4.

## 6. State surgery is its own approval gate

`pulumi state delete`, `pulumi state rename`, `pulumi import`, and
`pulumi refresh` change what Pulumi believes about reality without
changing reality itself (or vice versa for `import` and `refresh`) — they
are mutating-class actions in their own right, never a silent step inside
a "fix." `pulumi refresh` in particular can look harmless (it only updates
state to match live infrastructure) but silently masks real drift if run
casually — it never touches the program, so a refresh that "fixes" a
preview by absorbing an out-of-band change can hide the actual root cause.
If evidence points at state/config divergence that needs one of these to
resolve, propose it as its own remediation option with its own risk,
steps, and rollback (per `remediation.md`'s option template) — do not fold
it into an unrelated option's Steps section.

---
description: Investigate an operational problem with the SRE agent — evidence-first, approval-gated
argument-hint: <problem description>
---

Invoke the `sre-agent` skill and start an incident investigation at Phase 1
(Understand and scope) for the following problem, exactly as the user stated
it:

$ARGUMENTS

If no problem description was provided, ask the user what operational problem
they are seeing before doing anything else. Follow the sre-agent skill's loop
and safety rules exactly — in particular: read-only until a remediation option
is explicitly approved.

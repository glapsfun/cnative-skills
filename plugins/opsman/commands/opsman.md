---
description: Start an opsman run — discover skills, select a team, and drive a test-first, evidence-gated execution loop
argument-hint: <task description>
---

Invoke the `opsman` skill, then start a run for the following task, exactly
as the user stated it:

$ARGUMENTS

If no task description was provided, ask the user what they want done before
doing anything else. Start the run with the kernel, quoting the task:

    <skill-dir>/scripts/opsman start "<task>"

Then follow the opsman skill's protocol exactly: work from the rendered
context packet (`opsman next`), record every outcome as a typed event via
`opsman record`, and never edit `.opsman/` files by hand.

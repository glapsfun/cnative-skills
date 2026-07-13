---
description: Start an opsman run — discover skills, select a team, and drive a test-first, evidence-gated execution loop
argument-hint: <task description>
---

Invoke the `opsman` skill, then start a run for the following task, exactly
as the user stated it:

$ARGUMENTS

If no task description was provided, ask the user what they want done before
doing anything else.

Before starting, determine the workspace mode:

1. If the arguments contain `--base branch`, `--base current`, or
   `--base worktree`, pass it through.
2. Otherwise ask the user (AskUserQuestion) which mode to use — offer
   `branch` (recommended: new opsman/<run-id> branch in this checkout),
   `current` (work on the current branch in place), and `worktree`
   (isolated .opsman worktree). Do not start until they choose.

If the arguments contain `--no-q`, pass it through as well. Then:

    <skill-dir>/scripts/opsman start --base <mode> [--no-q] -- "<task>"

Then follow the opsman skill's protocol exactly: work from the rendered
context packet (`opsman next`), record every outcome as a typed event via
`opsman record`, and never edit `.opsman/` files by hand.

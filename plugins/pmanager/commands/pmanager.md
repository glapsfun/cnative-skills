---
description: Turn a problem or idea into a managed spec (epic, plan, tasks) — or track an existing one
argument-hint: <problem, idea, or status/update request>
---

Invoke the `pmanager` skill and start at Phase 0 (Bootstrap memory) for the
following request, exactly as the user stated it:

$ARGUMENTS

If no request was provided, ask the user what problem, idea, or tracked epic
they want to work on before doing anything else. Follow the pmanager skill's
loop exactly — in particular: research before interviewing, and do not write
plan.md or any task file until the epic framing is explicitly approved
(non-interactive runs follow the skill's degraded rule instead: proceed with
the epic marked `draft` and say the framing awaits approval).

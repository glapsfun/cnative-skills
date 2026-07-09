---
description: Resume an opsman run — rebuild state from the journal and continue from the handoff
argument-hint: [run-id]
---

Invoke the `opsman` skill, then reattach to the run:

    <skill-dir>/scripts/opsman resume $ARGUMENTS

If the kernel exits 2 because no run pointer exists, show the user the run
ids it listed and ask which one to resume. Once resume prints the handoff
(and, for active runs, the current role packet), follow the opsman skill's
protocol from exactly that state — never re-plan work the journal already
records, and never edit `.opsman/` files by hand.

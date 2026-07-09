---
description: Show the status of the active opsman run
---

Invoke the `opsman` skill, then run:

    <skill-dir>/scripts/opsman status

Summarize the output for the user: run id, current state, and task. If the
run is in a terminal state (COMPLETED, BLOCKED, ABANDONED), point at the
run's `result.md`, which contains the verdict and budget usage. Take no
other action — this command only reports.

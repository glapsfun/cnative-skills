---
description: Run the active opsman run's acceptance checks and report the evidence
---

Invoke the `opsman` skill, then run:

    <skill-dir>/scripts/opsman validate

Report each acceptance check's pass/fail with the evidence directory the
kernel printed. If the kernel refuses (for example exit 3 because the run
is not in a phase that executes checks), relay its message verbatim. Do not
fix anything from this command — report, and remind the user the run
continues via `/opsman-resume`. Take no action beyond reporting.

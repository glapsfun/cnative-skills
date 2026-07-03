# Load Validation (k6)

After passive validation passes, optionally prove the fix holds under
representative load — the difference between "pods are healthy at idle" and
"the incident will not recur at Monday-morning traffic".

**Load generation is mutation-class.** It gets its own approval gate; never
target production unless the user explicitly says so; every proposal states
the target environment, RPS, duration, and blast radius before asking for
approval.

## Thresholds from expected behavior

Map the ledger's expected-behavior criteria 1:1 into k6 thresholds:

```javascript
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: 50, // requests per second — justify against normal traffic
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 100,
    },
  },
  thresholds: {
    http_req_duration: ['p(99)<300'], // ledger: p99 < 300ms
    http_req_failed: ['rate<0.01'], // ledger: error rate < 1%
  },
};

export default function () {
  http.get(`${__ENV.TARGET_URL}/`);
  sleep(0.1);
}
```

Scenario choice follows the incident shape:

- **`constant-arrival-rate`** — steady reproduction of normal traffic.
- **`ramping-arrival-rate`** spike profile — when the incident was
  traffic-triggered; ramp to the RPS that broke it.
- **Long soak** (30–60 min at moderate rate) — when the root cause was a
  leak; watch the memory slope, not just thresholds.

## Execution paths

Local CLI:

```bash
k6 run -e TARGET_URL=https://staging.example.com script.js
```

k6-operator (when the `testruns.k6.io` CRD exists) — applying these
manifests is a mutation, covered by the same approval:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: incident-validation-script
  namespace: k6
data:
  script.js: |
    <the script above>
---
apiVersion: k6.io/v1alpha1
kind: TestRun
metadata:
  name: incident-validation
  namespace: k6
spec:
  parallelism: 1
  script:
    configMap:
      name: incident-validation-script
      file: script.js
```

Neither available: print the script with run instructions and let the user
execute it wherever their load tooling lives.

## Reading results

- Threshold pass/fail maps directly into the ledger's validation table —
  one row per threshold, alongside the passive criteria.
- Record p95/p99, error rate, achieved RPS, and iteration count in the
  final report.
- A failed threshold = validation failed → back to Phase 3 with the load
  profile recorded as the reproduction recipe (that is valuable evidence).

## Guardrails

- Start at ≤50% of normal production RPS and step up only if healthy.
- Watch the golden signals live during the run (queries from
  `prometheus-analysis.md`) — abort on error-rate or saturation runaway,
  don't wait for the run to finish.
- State the abort command up front: `Ctrl+C` locally,
  `kubectl delete testrun incident-validation -n k6` for the operator.
- Never run against production without the user explicitly saying the word.

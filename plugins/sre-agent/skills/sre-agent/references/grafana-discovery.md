# Grafana Discovery

Find what dashboards, datasources, and alert rules already exist before
building queries from scratch — the organization's dashboards encode its real
metric names, label conventions, and what "normal" looks like.

## Authentication

All API calls use a service-account token header:

```bash
curl -fsS -H "Authorization: Bearer $GRAFANA_TOKEN" 'http://localhost:3000/api/health'
```

The token comes from the user, or from an existing Secret they point you at —
reference the Secret by **name**, never print its value. Anonymous read
access sometimes works in dev instances; try `/api/health` without a token
first.

## API recipes

Port-forward Grafana (`kubectl port-forward -n <ns> svc/grafana 3000:3000`),
then:

```bash
# Search dashboards mentioning the app
curl -fsS -H "Authorization: Bearer $GRAFANA_TOKEN" \
  'http://localhost:3000/api/search?query=$WORKLOAD&type=dash-db'

# Fetch a dashboard's full JSON by uid (from the search result)
curl -fsS -H "Authorization: Bearer $GRAFANA_TOKEN" \
  'http://localhost:3000/api/dashboards/uid/<uid>'

# List datasources — names and types only, to learn what backends exist
curl -fsS -H "Authorization: Bearer $GRAFANA_TOKEN" \
  'http://localhost:3000/api/datasources' | head -c 2000

# Provisioned alert rules
curl -fsS -H "Authorization: Bearer $GRAFANA_TOKEN" \
  'http://localhost:3000/api/v1/provisioning/alert-rules'

# Health (no auth usually required)
curl -fsS 'http://localhost:3000/api/health'
```

## Mining dashboards for queries

The fastest route to correct PromQL for an unfamiliar app: pull the
dashboard JSON and extract the panel queries —

```bash
curl -fsS -H "Authorization: Bearer $GRAFANA_TOKEN" \
  'http://localhost:3000/api/dashboards/uid/<uid>' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["dashboard"];
print("\n".join(t.get("expr","") for p in d.get("panels",[]) for t in p.get("targets",[]) if t.get("expr")))'
```

These expressions carry the app's **real** metric names and label selectors —
adapt them (swap the dashboard's template variables for concrete
namespace/workload values) instead of guessing metric names. The same works
for LogQL panels backed by Loki datasources.

Dashboards also encode expected ranges: a panel titled "p99 latency" with a
threshold line at 500ms tells you what the team considers normal — useful
when defining expected behavior in Phase 4.

## When Grafana is absent

Skip dashboard discovery, note it in the ledger, and fall back to metric
discovery in `prometheus-analysis.md` (`/api/v1/label/__name__/values` with a
namespace matcher) to learn the app's metric names directly from Prometheus.

# ELK / OpenSearch Investigation

The logs path for environments that ship logs to Elasticsearch or OpenSearch
instead of Loki. Same investigation goals as `logs-investigation.md`: error
signatures, first-occurrence timestamps, error-rate trend.

Reach the cluster:

```bash
kubectl port-forward -n <ns> svc/elasticsearch 9200:9200   # or svc/opensearch
```

Auth: most production clusters require it. Use an API key header —
`-H 'Authorization: ApiKey $ES_API_KEY'` (or basic auth) — where the key
comes from the user or a Secret **name** they point you at; never print
secret values. `/_cluster/health` without credentials returning 401/403 just
means "get credentials", not "broken".

## Index discovery

```bash
# Newest indices first — find the pattern covering the app
curl -fsS 'localhost:9200/_cat/indices?v&s=creation.date:desc' | head -20

# Data streams (modern setups)
curl -fsS 'localhost:9200/_data_stream' | head -c 2000
```

Common patterns: `logs-*`, `filebeat-*`, `logstash-*`, `app-*`. Pick the one
whose newest index is actively growing.

## Error hunting (query DSL)

```bash
curl -fsS -H 'Content-Type: application/json' 'localhost:9200/$INDEX/_search' -d '{
  "size": 50,
  "sort": [{"@timestamp": "asc"}],
  "query": {"bool": {"filter": [
    {"range": {"@timestamp": {"gte": "2026-07-03T08:00:00Z", "lte": "2026-07-03T11:00:00Z"}}},
    {"query_string": {"query": "level:(error OR fatal) OR message:(*exception* OR *panic* OR \"connection refused\" OR timeout)"}}
  ]}}
}'
```

Scope to the workload with an extra filter term when the mapping has it:
`{"term": {"kubernetes.namespace": "$NS"}}` /
`{"wildcard": {"kubernetes.pod.name": "$WORKLOAD*"}}`.

## Error-rate trend

When did errors start? Bucket the same filter by time:

```bash
curl -fsS -H 'Content-Type: application/json' 'localhost:9200/$INDEX/_search' -d '{
  "size": 0,
  "query": {"bool": {"filter": [
    {"range": {"@timestamp": {"gte": "2026-07-03T06:00:00Z", "lte": "2026-07-03T11:00:00Z"}}},
    {"query_string": {"query": "level:(error OR fatal)"}}
  ]}},
  "aggs": {"errors_over_time": {"date_histogram": {"field": "@timestamp", "fixed_interval": "5m"}}}
}'
```

The first bucket with an elevated count is the first-occurrence timestamp —
hand it to the timeline in `root-cause-analysis.md`.

## Field discovery

Field names vary per pipeline. Before trusting an empty result:

```bash
curl -fsS 'localhost:9200/$INDEX/_mapping' | head -c 3000   # what fields exist
curl -fsS 'localhost:9200/$INDEX/_search?size=1'            # one sample document
```

Look for the actual level field (`level`, `log.level`, `severity`), message
field (`message`, `msg`), and Kubernetes metadata fields
(`kubernetes.namespace`, `kubernetes.pod.name`).

## Elasticsearch vs OpenSearch

Every API above is identical on both. `GET /` distinguishes them (`version.
distribution: opensearch`). Auth-failure codes differ across setups (401 vs
403) — both mean "ask the user for credentials". Kibana/OpenSearch
Dashboards, when discovered, can serve the same dashboard-mining role as
Grafana (`grafana-discovery.md`) but v2 does not automate it — note it as an
option for the user.

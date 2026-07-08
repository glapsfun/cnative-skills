# shellcheck shell=sh
# jq-based JSON helpers. jq is a hard dependency of every caller.

json_valid() {
  jq -e . "$1" >/dev/null 2>&1
}

# Shallow schema check: every key in the schema's `required` array must be
# present in the document. Full JSON Schema validation is out of scope in v1.
schema_check() {
  jq -e --slurpfile _s "$1" \
    '. as $doc | all(($_s[0].required // [])[]; . as $k | $doc | has($k))' \
    "$2" >/dev/null 2>&1
}

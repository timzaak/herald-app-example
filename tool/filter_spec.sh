#!/usr/bin/env bash
# Filter an OpenAPI spec: keep only paths matching given prefixes, and the
# schemas they transitively reference (via $ref). Everything else is dropped.
#
# Usage:
#   tool/filter_spec.sh <input.json> <output.json> [prefix ...]
# Default prefix: /api/auth
#
# Requires: jq
set -euo pipefail

INPUT="${1:-}"
OUTPUT="${2:-}"
shift 2 || true
PREFIXES=("$@")
if [ ${#PREFIXES[@]} -eq 0 ]; then
  PREFIXES=("/api/auth")
fi

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
  echo "Usage: $0 <input.json> <output.json> [prefix ...]" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

# Pass prefixes to jq as a JSON array of strings.
prefixes_json=$(printf '%s\n' "${PREFIXES[@]}" | jq -R . | jq -s .)

jq --argjson prefixes "$prefixes_json" '
  def collect_refs:
    [.. | objects | select(has("$ref")) | ."$ref"] | unique;

  def schema_name(ref): ref | sub("^#/components/schemas/"; "");

  def matches_prefix($p):
    $prefixes | any(. as $px | $p | startswith($px));

  (.paths | to_entries | map(select(.key | matches_prefix(.)))) as $kept_paths
  | (.components.schemas // {}) as $all_schemas

  # BFS: start from refs in kept paths, expand inner refs of each schema.
  | (reduce range(0; 2000) as $_ (
      {todo: ($kept_paths | map(.value) | collect_refs), keep: ([])}
    ;
      (if (.todo | length) == 0 then . else
        (.todo[0]) as $cur
        | .todo |= .[1:]
        | (if (.keep | index($cur)) == null then
            .keep += [$cur]
            | ($all_schemas[$cur | schema_name(.)] // {}) as $sch
            | .todo = ((.todo + ([ $sch ] | collect_refs)) | unique)
          else . end)
      end)
    )) as $walk

  # Tags actually used in kept paths.
  | ([ $kept_paths | to_entries[]
      | .value | to_entries[]
      | select(.key | IN("get","post","put","delete","patch"))
      | .value.tags // [] ] | add // [] | unique) as $used_tags

  | {
      openapi: .openapi,
      info: .info,
      servers: (.servers // []),
      tags: [ .tags[]? | select(.name as $n | $used_tags | index($n)) ],
      paths: ($kept_paths | from_entries),
      components: {
        securitySchemes: (.components.securitySchemes // {}),
        schemas: ( .components.schemas
          | to_entries
          | map(select(.key as $k
              | $walk.keep | map(schema_name(.)) | index($k)))
          | from_entries )
      }
    }
' "$INPUT" > "$OUTPUT"

echo "Filtered $INPUT -> $OUTPUT"
echo "Paths kept:   $(jq '.paths | length' "$OUTPUT")"
echo "Schemas kept: $(jq '.components.schemas | length' "$OUTPUT")"

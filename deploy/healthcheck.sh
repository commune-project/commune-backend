#!/bin/sh
set -eu

CONFIG=${COMMUNE_CONFIG:-/run/commune/config.json}
HEALTH_URL=${COMMUNE_HEALTH_URL:-http://127.0.0.1:8080/health/ready}
HOST=$(jq -r '.sites[0].origin | sub("^https://"; "")' "$CONFIG")

if [ -z "$HOST" ] || [ "$HOST" = "null" ]; then
  echo "commune-healthcheck: no configured site" >&2
  exit 1
fi

exec curl -fsS --max-time 4 -o /dev/null -H "Host: $HOST" "$HEALTH_URL"

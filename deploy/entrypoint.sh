#!/bin/sh
set -eu

TEMPLATE=${COMMUNE_CONFIG_TEMPLATE:-/etc/commune/config.template.json}
CONFIG=${COMMUNE_CONFIG:-/run/commune/config.json}
COMMUNE_BIN=${COMMUNE_BIN:-/usr/local/bin/commune}

if [ ! -r "$TEMPLATE" ]; then
  echo "commune-entrypoint: config template not readable: $TEMPLATE" >&2
  exit 1
fi

db_password=${COMMUNE_DB_PASSWORD:-}
if [ -n "${COMMUNE_DB_PASSWORD_FILE:-}" ]; then
  db_password=$(tr -d '\r\n' < "$COMMUNE_DB_PASSWORD_FILE")
fi
if [ -z "$db_password" ]; then
  echo "commune-entrypoint: COMMUNE_DB_PASSWORD or COMMUNE_DB_PASSWORD_FILE is required" >&2
  exit 1
fi

# The password is embedded in a URL, so percent-encode it with jq @uri.
encoded_password=$(printf '%s' "$db_password" | jq -Rsr @uri)
database_url="postgres://${COMMUNE_DB_USER:-commune}:${encoded_password}@${COMMUNE_DB_HOST:-postgres}:${COMMUNE_DB_PORT:-5432}/${COMMUNE_DB_NAME:-commune}?sslmode=${COMMUNE_DB_SSLMODE:-disable}"

smtp_password=${COMMUNE_SMTP_PASSWORD:-}
if [ -n "${COMMUNE_SMTP_PASSWORD_FILE:-}" ]; then
  smtp_password=$(tr -d '\r\n' < "$COMMUNE_SMTP_PASSWORD_FILE")
fi

mkdir -p "$(dirname "$CONFIG")"
jq --arg database_url "$database_url" --arg smtp_password "$smtp_password" '
  .database_url = $database_url
  | if ((.smtp.password? // "") == "__SMTP_PASSWORD__") then
      .smtp.password = $smtp_password
    else
      .
    end
' "$TEMPLATE" > "$CONFIG"
chmod 0600 "$CONFIG"

subcommand=${1:-serve}
if [ "$#" -gt 0 ]; then
  shift
fi

exec "$COMMUNE_BIN" "$subcommand" "$CONFIG" "$@"

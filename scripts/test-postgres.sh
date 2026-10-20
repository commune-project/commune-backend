#!/usr/bin/env bash
set -euo pipefail

# Own the entire cluster so tests never touch a developer's existing database.
test_root=$(mktemp -d /tmp/commune-postgres.XXXXXX)
cleanup() {
  pg_ctl -D "$test_root/data" -m fast -w stop >/dev/null 2>&1 || true
  rm -rf -- "$test_root"
}
trap cleanup EXIT
mkdir "$test_root/socket"
initdb -D "$test_root/data" -A trust -U commune_test --no-locale -E UTF8 >"$test_root/init.log"
if ! pg_ctl -D "$test_root/data" -l "$test_root/server.log" \
    -o "-k $test_root/socket -p 55439 -h ''" -w start; then
  cat "$test_root/server.log"
  exit 1
fi
export COMMUNE_TEST_POSTGRES_DSN="host=$test_root/socket port=55439 user=commune_test dbname=postgres sslmode=disable connect_timeout=5"
go test ./... -count=1

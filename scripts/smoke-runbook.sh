#!/usr/bin/env bash
set -euo pipefail

binary=/tmp/commune-mygo-build/commune
test_root=$(mktemp -d /tmp/commune-runbook.XXXXXX)
db_port=55441
http_port=58441
config=$test_root/config.json
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -TERM "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  pg_ctl -D "$test_root/data" -m fast -w stop >/dev/null 2>&1 || true
  rm -rf -- "$test_root"
}
trap cleanup EXIT

initdb -D "$test_root/data" -A trust -U commune_test --no-locale -E UTF8 >"$test_root/init.log"
mkdir "$test_root/socket"
if ! pg_ctl -D "$test_root/data" -l "$test_root/postgres.log" \
    -o "-k $test_root/socket -p $db_port -h 127.0.0.1" -w start >/dev/null; then
  cat "$test_root/postgres.log"
  exit 1
fi

cat >"$config" <<JSON
{
  "sites": [{"id": "a", "origin": "https://a.example", "aliases": []}],
  "database_url": "postgres://commune_test@127.0.0.1:$db_port/postgres?sslmode=disable",
  "trusted_proxies": [],
  "runtime": {
    "listen": "127.0.0.1:$http_port",
    "read_timeout_seconds": 15,
    "write_timeout_seconds": 30,
    "idle_timeout_seconds": 60,
    "shutdown_timeout_seconds": 10,
    "max_body_bytes": 1048576,
    "max_page_size": 100,
    "workers": 1
  },
  "federation": {
    "allow_private_network": false,
    "fetch_timeout_seconds": 10,
    "max_fetch_bytes": 1048576,
    "max_redirects": 5,
    "clock_skew_seconds": 300
  }
}
JSON

wait_ready() {
  local attempt=0
  while ((attempt < 50)); do
    if [[ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: a.example' "http://127.0.0.1:$http_port/health/ready")" == "204" ]]; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 0.2
  done
  return 1
}

"$binary" check-config "$config"
"$binary" migrate "$config"
"$binary" migrate "$config"
"$binary" provision-sites "$config"
COMMUNE_ADMIN_PASSWORD=runbook-admin-password "$binary" provision-admin "$config" a alice
COMMUNE_ACCOUNT_PASSWORD=runbook-account-password "$binary" provision-account "$config" a bob bob@example.org

"$binary" serve "$config" >"$test_root/server-1.log" 2>&1 &
server_pid=$!
wait_ready
[[ "$(curl -sS -o /dev/null -w '%{http_code}' -H 'Host: a.example' "http://127.0.0.1:$http_port/health/live")" == "204" ]]
accounts_before=$(psql "postgres://commune_test@127.0.0.1:$db_port/postgres?sslmode=disable" -Atc 'SELECT count(*) FROM accounts')
sites_before=$(psql "postgres://commune_test@127.0.0.1:$db_port/postgres?sslmode=disable" -Atc 'SELECT count(*) FROM sites')
kill -TERM "$server_pid"
wait "$server_pid"
server_pid=""

"$binary" serve "$config" >"$test_root/server-2.log" 2>&1 &
server_pid=$!
wait_ready
accounts_after=$(psql "postgres://commune_test@127.0.0.1:$db_port/postgres?sslmode=disable" -Atc 'SELECT count(*) FROM accounts')
sites_after=$(psql "postgres://commune_test@127.0.0.1:$db_port/postgres?sslmode=disable" -Atc 'SELECT count(*) FROM sites')
[[ "$accounts_before" == "2" && "$accounts_after" == "$accounts_before" ]]
[[ "$sites_before" == "1" && "$sites_after" == "$sites_before" ]]

echo "runbook smoke: fresh migration, populated restart and graceful shutdown passed"

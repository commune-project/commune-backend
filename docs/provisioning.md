# Explicit migrations and provisioning

Build with `make build`. Configure canonical sites and PostgreSQL in the JSON
file described by [configuration](configuration.md). Against a new database:

```sh
/tmp/commune-mygo-build/commune migrate config/example.json
/tmp/commune-mygo-build/commune provision-sites config/example.json
```

The migration command is explicit; provisioning checks the current schema
without changing it. Normal serving will not perform either operation.
Repeated site provisioning retains canonical identities and rejects conflicting
origins or authorities. It does not remove existing aliases or sites.

To create an initial administrator for site `a`, supply a password through
`COMMUNE_ADMIN_PASSWORD` and execute:

```sh
/tmp/commune-mygo-build/commune provision-admin config/example.json a alice
```

The environment variable must be supplied by the operator's shell or secret
manager; passwords are never command arguments or log output. Passwords must
contain 12–72 bytes and are stored with bcrypt at its default cost of 10.
The environment variable is an operator provisioning input, not a browser
authentication mechanism.

This creates a site-owned Person and account and grants only site administration.
An identical username at another site has an independent actor, account and
password. Repetition with matching credentials preserves the existing hash;
different credentials or a disabled account fail and roll back. Provisioning
does not implicitly reset credentials.

Deployment-wide authority requires an explicit extra flag:

```sh
/tmp/commune-mygo-build/commune provision-admin config/example.json a alice --deployment-superadministrator
```

The flag grants the separate deployment role without sharing authentication
across sites. New grants create audit events in their applicable scope.
Repeated grants do not duplicate assignments or audit entries.

All provisioning changes within a site/account operation use one GORM
transaction. Concurrent provisioning of an account serializes with a database
advisory lock. The configured-sites command applies each site in its own
transaction; a later site's conflict does not undo earlier successful sites.

`make test-postgres` verifies migration/constraint behavior, actor-URI remote
managers, local-only isolation, independent credentials, repeat provisioning,
rejected replacement, explicit deployment authority and scoped audit entries.
An initial HTTP health server is available:

```sh
/tmp/commune-mygo-build/commune serve config/example.json
```

It rejects incompatible schemas before serving, routes only configured sites,
and provides GET `/health/live` and `/health/ready`. Readiness performs a
bounded database ping and schema check. Runtime timeouts and header limits
apply, logs use structured JSON without raw database errors, and SIGINT/SIGTERM
initiate a bounded graceful shutdown. No migration or seeding runs at startup.

CLI/HTTP smoke evidence on 2026-10-14: migration and provisioning ran against
a separate PostgreSQL 18.6 database; live/ready returned 204, an unknown Host
returned 404, SIGINT produced a clean exit, and restarting returned ready 204.
One account and its single site role remained unchanged; no deployment role
was inferred. The fixture database and service were removed/stopped afterward.

Delivery workers use expiring leases. `worker_test.mygo` verifies that a live
lease is not claimed twice, an expired lease is reclaimed after restart, a
recovered job completes, and exhausted work reaches a durable reported failure.
Claims, retries and terminal failures emit structured logs with activity,
recipient, attempt and reason categories; payload bodies and keys are not
logged. `server_test.mygo` verifies live/readiness routing, bounded readiness,
runtime limits and redacted error responses.

# Deployment runbook

This runbook covers the current Commune backend. Commands fail closed when the
configuration or database schema is incompatible; normal serving never migrates,
seeds, clears tables, or changes account credentials.

## Prerequisites

- Go 1.27.1.
- A MyGO checkout at `../../mygo`, or a `MYGO_ROOT` override matching the local
  `replace` path used by the build.
- PostgreSQL with `initdb` and `pg_ctl` for the isolated test suite. The local
  baseline is PostgreSQL 18.6.
- A canonical HTTPS origin for every site. Local development may use test-only
  private-network federation with `allow_private_network`; this must remain off
  in production.

Build and check the protocol snapshots and full PostgreSQL suite with:

```sh
make verify
```

`make verify` regenerates MyGO output, builds the compiler and server, verifies
snapshot digests, runs the complete PostgreSQL-backed test suite, and checks
tracked generated files for drift. CI uses the same target.

`make smoke-runbook` independently exercises this runbook against a fresh
PostgreSQL cluster: first and repeated migration, site/administrator/account
provisioning, readiness, SIGTERM shutdown, process restart and unchanged
populated counts.

## Configuration

Start from `config/example.json` and keep the real file outside public source
control when it contains credentials. Restrict its filesystem permissions.

Each configured site has a unique lowercase id and canonical HTTPS origin.
Aliases share the same uniqueness namespace. Forwarded hosts are accepted only
from configured trusted proxy CIDRs. Invalid origins, duplicate domains,
unknown keys, missing limits and malformed database URLs stop startup without
echoing secrets.

Validate without connecting to PostgreSQL or serving traffic:

```sh
/tmp/commune-mygo-build/commune check-config /secure/commune.json
```

## First deployment

Use one PostgreSQL database for a deployment. Multiple sites share normalized
objects but retain independent accounts, sessions, reception and moderation.

```sh
/tmp/commune-mygo-build/commune migrate /secure/commune.json
/tmp/commune-mygo-build/commune provision-sites /secure/commune.json
COMMUNE_ADMIN_PASSWORD='replace-me' \
  /tmp/commune-mygo-build/commune provision-admin \
  /secure/commune.json site-a alice
COMMUNE_ACCOUNT_PASSWORD='replace-me' \
  /tmp/commune-mygo-build/commune provision-account \
  /secure/commune.json site-a bob bob@example.org
```

Append `--deployment-superadministrator` only when an explicit deployment-wide
administrator is intended. Provisioning is idempotent for site metadata but
will not silently replace an existing credential or escalate an ordinary site
role.

Run migrations before provisioning or serving. There is no automatic migration
at startup. A schema checksum mismatch, missing migration, or extra required
migration makes readiness fail and prevents serving.

## Access modes

Federation participation and read/post policy are independent dimensions.

| Community | Read | Post |
| --- | --- | --- |
| Local-only, all users | Authenticated owning-site users | Same users |
| Local-only, members | Approved owning-site members | Same members |
| Local-only, readers | Authenticated owning-site users | Approved owning-site members |
| Federated, all users | Public ActivityPub or eligible authenticated actors | Eligible authenticated actors |
| Federated, members | Current approved verified members or applicable managers | Same members |
| Federated, readers | Public read | Current approved verified members |

Anonymous users, remote actors and ordinary accounts of another colocated site
never receive local-only access. Local-only communities and their objects,
contexts, counts, members and delivery jobs have no ActivityPub representation
or synchronization path.

Member-readable federation uses actor-signed reads and personal-inbox delivery.
An instance key does not delegate access for every actor at that instance.
Current membership, community policy and management roles are checked on every
read and again before pending delivery. Revoking access stops new reads and
delivery; it cannot erase copies another server already received or cached.

## Management scopes

| Scope | Authority |
| --- | --- |
| Deployment superadministrator | Explicitly assigned; manages hosted sites and communities |
| Site administrator | Manages one site and communities hosted there |
| Community creator | Manages the assigned community |
| Community administrator | Manages the assigned community, under the same scope |

Community managers cannot grant deployment/site roles or rewrite another
author's body. Federated community creators and administrators may be remote
actors and manage across servers only while the host's current role record
authorizes the action. Sharing a hostname, possessing a valid key, or being an
unrelated server administrator grants no community authority. Elevated
management actions are audited with acting actor and scope.

## Lifecycle and recovery

Start the server after migration:

```sh
/tmp/commune-mygo-build/commune serve /secure/commune.json
```

GET `/health/live` returns readiness of the process; GET `/health/ready` requires
a bounded database ping and compatible schema. Unknown Host values receive 404.
SIGINT and SIGTERM stop new requests and initiate bounded graceful shutdown.

Inbound activities are durably recorded before acknowledgement. Delivery jobs
use expiring leases. A process crash leaves unfinished jobs reclaimable after
the lease expires; committed deliveries are not lost on restart. Claims,
retries and terminal failures emit structured logs containing activity,
recipient, attempt and reason categories. Activity bodies, credentials and
private keys are not logged.

`make test-postgres` starts a fresh temporary cluster, applies migrations, runs
all tests, then stops and removes the cluster. Tests cover repeat migration,
populated data surviving repository reopen, lease reclaim after simulated
restart, and permanent failure retention. This is local recovery evidence, not
live peer interoperability evidence.

## Backup, retention and rollback

Take a consistent PostgreSQL backup with `pg_dump` before migration, policy
changes, or binary upgrades:

```sh
pg_dump --format=custom --file=commune-before-upgrade.dump "$COMMUNE_DATABASE_URL"
```

Verify restores on a separate temporary database before relying on the backup.
Object bodies are stored once per canonical URI, while immutable activity
payloads and per-site receptions can consume additional space. Completed rows
and inbound/outbound audit state have no automatic garbage collector in this
change; operators must retain enough protocol history for pending delivery,
moderation and investigation and apply a reviewed retention policy appropriate
to their deployment. Never remove payloads referenced by unfinished jobs.

Migrations in this change are forward-only. Roll back an incompatible release by
restoring the pre-upgrade backup and deploying the previous binary against its
matching schema. Reverting only the binary while retaining a newer incompatible
schema fails readiness; normal startup does not undo migrations automatically.

## Verification checklist

1. Run `make verify` on the release commit.
2. Validate the real configuration with `check-config`.
3. Back up a populated database, migrate it, and verify repeated migration and
   readiness.
4. Confirm existing accounts, posts, subscriptions and queued work remain after
   restart.
5. Exercise live/ready failure with a stopped database and schema mismatch.
6. Confirm SIGTERM closes the listener and an expired delivery lease is
   reclaimed on restart.
7. Test all local-only modes and the applicable federated modes with accounts
   from the owning site and a colocated second site.
8. Keep live peer results separate from fixture tests and record exact peer
   release or image digests.

# Persistence foundation

The persistence layer uses GORM v1.31.2 and its PostgreSQL driver v1.6.0.
Repository behavior and persistence records are written in MyGO; generated
Go is checked in. The small handwritten `migrationfiles` adapter only embeds
SQL text so the binary does not depend on its working directory.

`internal/storage/gorm.mygo` configures a PostgreSQL connection pool without
opening a network connection during configuration. The caller must perform
bounded readiness checks and close the pool on shutdown. GORM SQL logging is
disabled to prevent query parameters or protected bodies from entering logs.
Connection pool limits are currently 16 open and 4 idle connections.

`FindAccount` binds both site id and username as query values, checks GORM's
Error and RowsAffected, and maps missing records to a typed Option. It is a
repository primitive, not a password authentication endpoint. Nullable email
uses sql.NullString; persistence records do not expose MyGO sum types to GORM.
Explicit table selection and column tags preserve migration naming.

`RunTransaction` passes the actual GORM transaction handle to MyGO work. All
operations belonging to the mutation must use that handle. Callback rejection
and panic roll back; success commits; begin and commit failures are returned.
The one-line inline Go defer ensures rollback even when the callback panics.
Successful commit makes the deferred rollback harmless.

## Explicit migrations

SQL migrations live in `internal/migrationfiles/migrations/`. The catalog
orders filenames explicitly and computes SHA-256 checksums of embedded bytes.
Migration execution uses GORM's underlying database/sql pool. The explicit
MigrateGORM API acquires a PostgreSQL transaction-scoped advisory lock, creates
the migration ledger, checks existing history, applies pending SQL and records
each checksum in one transaction. Failure rolls back the complete attempt.

The public schema is selected explicitly during migration. Current binaries
refuse missing, older, newer, renamed or checksum-mismatched migration history
through CheckGORM. Schema checking reads only and never runs DDL. Applied SQL
files must not be edited; add a forward migration instead. AutoMigrate is not
called. Normal serving will only check schema compatibility.

The first migration defines sites, routing authorities, canonical actors,
site-local accounts and sessions, independent site/deployment role tables,
audit records and site-scoped actor/domain blocks. Composite foreign keys bind
accounts, sessions and site roles to their owning site. A site administrator
assignment never creates a deployment superadministrator assignment.

## Evidence and pending work

`make test` uses sqlmock v1.5.2 for SQL expectations and failure injection,
including begin/query/scan/DDL/ledger/commit failures and panic rollback.
It checks parameter binding, read-only schema checking, and repeat migrations
without DDL replay. Pure-Go SQLite via glebarez/sqlite v1.11.0 executes actual
GORM repository reads, nullable mapping, site isolation and commit/rollback.
Its test-only schema does not replace PostgreSQL migrations.

`make test-postgres` creates and removes its own temporary PostgreSQL cluster.
It verifies actual initial/repeated migrations, readiness, checksum rejection,
transactional DDL rollback, per-site username/email uniqueness, actor kind
and ownership, remote private-key rejection, cross-site session/role rejection,
and explicitly separated deployment roles. Verified with PostgreSQL 18.6.
All test scenarios and assertions are MyGO.

To use a dedicated existing test server, set `COMMUNE_TEST_POSTGRES_DSN` to a
PostgreSQL keyword/value DSN. Its user must have CREATEDB permission; tests
create and drop uniquely named databases, never reset existing schemas.
Without this variable ordinary `make test` skips real PostgreSQL tests.
Migration 014 adds the verified `actors.acct` handle and the site-scoped durable
`actor_handle_jobs` queue used by asynchronous WebFinger resolution. Existing
actors start with an empty handle; no historical rows are rewritten.
Migrations 002 and 003 add forum identities and relationships: communities,
posts, contexts, memberships, moderators, follows, site reception, audiences,
verified inclusion, reactions, activities, original payloads, receipts and jobs.
Constraints separate local-only resources from protocol identities and block
cross-site local membership/reception, restricted relationship widening,
forged inclusion authority, activity/payload mutation and tombstone resurrection.
Remote Person actors may be federated creators, members and administrators.
These schema constraints supplement application authorization; they do not
establish verified network identity, current membership read access or delivery.

Explicit provisioning is implemented and tested; see [operator commands](provisioning.md).
Tasks 2.2–2.4 are complete. Peer federation infrastructure and the public server
are not yet implemented.

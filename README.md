# Commune MyGO

A MyGO backend for multi-site federated forums. Implementation follows
`openspec/changes/build-mygo-federated-forum-backend/`. The current executable
provides configuration validation, explicit migrations, site/administrator
provisioning, independent browser authentication, local forum APIs, FEP-1b12
Group federation, FEP-7888 discussion contexts, protected member delivery,
durable inbound/outbound work and lifecycle health endpoints. Live Lemmy,
Mastodon and Misskey compatibility remains pending pinned-peer verification.

[Participation APIs](docs/participation-api.md) cover email verification,
profiles and avatars, search, notifications, sanitized Markdown, and attachments.
See [configuration](docs/configuration.md) before enabling registration,
authoritative local media storage, or background workers.

## Development toolchain

Write application code and tests in MyGO. Prefer pure functions, immutable
values, pattern matching on `Option`/`Result`, and collection transformations.
Keep mutation and side effects at I/O boundaries; use loops when they express
ordered I/O more clearly. Handwritten Go is reserved for small adapters needed
by Go interfaces or compiler limitations. Generated Go remains compiler output.

- Go 1.27.1 (the application module requires Go 1.27).
- Local MyGO checkout at `../../mygo`, with its default bootstrap compiler.
- Baseline compiler commit: `4c52bc530dd247ad7dd7729c6099211319f85372`.
- FFI probes verified with compiler commit `77319e6bc3c7ed95087011bf3ebd6e9243255840`;
  see [probe evidence](docs/infrastructure-probes.md).
- Current application and early-Err regression verified with compiler commit
  `ec912b1849a3b5be95f254376bb29e0f8518ee2f`.
- Transitive MyGO return types and inferred numeric width reverified without
  workarounds with compiler commit `6cbefeecb8cb9fd75518b320051b7b54fdb5b69a`.
  The Go interface cast attached to a struct literal remains open.
- Forum/context/backfill integration and `make verify` were verified with local
  MyGO commit `e19e0a635bad0628a4c8ab239a1f317d22c3b27e`.

Build the compiler from source rather than relying on an untracked binary:

```sh
make build
/tmp/commune-mygo-build/commune check-config config/example.json
make test
make test-postgres
make verify
```

`make generate` refreshes the checked-in generated Go files. Never edit those
files manually. Set `MYGO_ROOT`, `BUILD_DIR` (an absolute path), or `GOCACHE`
to override development defaults. Build outputs and the writable Go cache
default to `/tmp`, outside the source tree. The Go module's local MyGO
replacement must resolve to the same checkout as `MYGO_ROOT`.

`make test-postgres` requires installed `initdb` and `pg_ctl`. It creates a
temporary PostgreSQL cluster with only a Unix socket, runs all tests, then stops
and removes that cluster. Verified locally with PostgreSQL 18.6. It does not
use an existing server. Pinned peer deployments are still required for live
federation tests; passing database tests does not establish interoperability.
Normal server startup must never delete data or seed demos.

The [protocol baseline](docs/protocol/baseline.md) records pinned mirror texts
and the requirement-to-test checklist. Verify their digests with
`make verify-protocol`.

[Configuration and routing](docs/configuration.md) describes the implemented
configuration schema, site isolation at the routing boundary, and proxy rules.

[Persistence foundation](docs/persistence.md) describes MyGO GORM repositories,
the explicit SQL migration runner, and the limits of the local transport tests.
[Provisioning](docs/provisioning.md) describes the explicit operator commands
and independently scoped administrator grants.
[Authentication](docs/authentication.md) describes ordinary account provisioning,
browser sessions, secure cookies and CSRF requirements.
[Permission checks](docs/permissions.md) records the implemented site repository
and independent community access policy, plus their integration boundaries.
[Forum storage](docs/forum-storage.md) records canonical object deduplication,
authoritative updates and community creation, with their pending API/transport
boundaries.
[Text rendering](docs/rendering.md) records the display sanitization boundary
and its separation from retained protocol payloads.
[Local HTTP API](docs/api.md) documents the versioned forum endpoints,
authentication rules, errors and pagination.
[Forum browser API](docs/forum-browser-api.md) specifies discovery, latest topics,
viewer permissions, interaction counts, management rosters and editing source.
[Federation discovery](docs/federation.md) documents WebFinger, actor and object
representations, tombstone and activity retrieval, and content negotiation.
[Discussion context profile](docs/protocol/context-profile.md) separates FEP-7888
behavior from Commune's direct-collection convention.
[Deployment runbook](docs/runbook.md) covers access modes, scopes, provisioning,
protected-peer limits, recovery, retention, backup and rollback.
Go dependencies are cached in `/tmp/commune-mygo-modcache` by default; set
`GOMODCACHE` to use another location.

All application test scenarios and assertions are written in MyGO. Unit tests
use sqlmock v1.5.2 and pure-Go SQLite via glebarez/sqlite v1.11.0.
`internal/testtransport` only bridges fixture construction and panic/recover; see
[compiler migration findings](docs/compiler-migration-issues.md) for verified
compiler issues and the boundaries preventing a complete migration.

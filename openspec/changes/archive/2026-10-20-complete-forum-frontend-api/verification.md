# Verification evidence

Verified on 2026-10-20. All application changes and acceptance tests are authored
in MyGO; generated Go was produced through the local compiler. The additional Go
testtransport helper only counts GORM statements and obtains PostgreSQL plans.

## Commands and results

With `ulimit -v 8000000`, writable task cache
`GOCACHE=/tmp/commune-frontend-api-gocache`, and
`GOMODCACHE=/tmp/commune-mygo-modcache`:

- `timeout 300 make build test test-postgres`: passed. This rebuilt the compiler,
  regenerated packages in Makefile order, built the server, ran all Go tests, and
  ran all tests against an isolated temporary PostgreSQL cluster.
- After final route cleanup and empty-page audit coverage, regenerated
  `internal/server` through `/tmp/commune-mygo-build/mygo sync internal/server`;
  `go build -o /tmp/commune-mygo-build/commune ./cmd/commune`, `go test ./...`, and
  `GOFLAGS=-v bash scripts/test-postgres.sh` all passed under a 180-second bound.
- `openspec validate complete-forum-frontend-api --strict`: passed.
- `git diff --check`: passed.

HTTP listener and PostgreSQL socket tests required execution outside the sandbox's
socket restriction. PostgreSQL tests used the existing script's private `/tmp`
cluster, which was stopped and deleted automatically.

## Acceptance mapping

| Tasks | Executable evidence |
| --- | --- |
| 1.1, 2.1 | `TestPostgresBrowserPolicyParity`: six federation/read/post combinations; anonymous, creator, member, explicit manager, ordinary user, foreign-site user, site administrator, and deployment administrator; SQL/read/write projection parity; member revocation and blocking |
| 1.2 | `TestBrowserUnavailableAuthentication`, `TestPostgresBrowserDiscoveryAndSource`, existing authentication tests: 503 on unavailable storage, cross-site session isolation, optional anonymous access |
| 1.3 | `TestPostgresBrowserInteractionsAndRosters`: current session roles and immediate revocation with unchanged cookies |
| 2.2, 2.4 | `TestPostgresBrowserDiscoveryAndSource`: public/local/restricted/foreign discovery, filtering before pagination, empty arrays, invalid pages, creation metadata, 405/Allow and no-store; `TestPostgresBrowserInteractionsAndRosters`: aggregate and empty addressed-page administrative audit |
| 2.3 | `TestPostgresBrowserFilteredPagesAndReplica`: hidden/deleted/removed/rejected exclusions, equal-timestamp stable paging, received versus unreceived replicas |
| 3.1 | `TestPostgresBrowserInteractionsAndRosters`, `TestPostgresBrowserFilteredPagesAndReplica`: like/undo state, idempotency, anonymous state, direct visible reply counts excluding hidden/deleted/removed/rejected/unreceived/nested replies |
| 3.2 | `TestPostgresBrowserDiscoveryAndSource`, `TestPostgresBrowserInteractionsAndRosters`, existing forum HTTP tests: detail/list/create/reply/edit/import DTOs, preserved safe display output and tombstone actions |
| 3.3 | `TestPostgresBrowserBatchQueries`: 1,000-topic fixture, fixed statement counts, analyzed PostgreSQL query plan |
| 4.1, 4.2 | `TestPostgresBrowserInteractionsAndRosters`: creator-only/assigned flags, creator deduplication, actor ordering and paging, revoked entries, anonymous/non-manager denials, retained mutation CSRF, administration separated from roster identity |
| 5.1, 5.2 | `TestPostgresBrowserDiscoveryAndSource`, `TestPostgresBrowserInteractionsAndRosters`: raw title/body round trip, empty reply title, 401/403/404, administrator non-author rejection, hidden/unreceived/deleted source denial, revoked read access |
| 6.1 | `docs/forum-browser-api.md`, updated authentication/API docs and README; examples use response shapes decoded by HTTP acceptance tests |
| 6.2–6.4 | Complete multi-package PostgreSQL suite, full build/unit tests, regeneration, strict validation and reviewed diff |

## Query evidence

For an authenticated creator, enrichment of one post and twenty posts each
executed exactly **3 statements**: community/relationship batch read, interaction
statistics batch read, and batched administrative audit insertion. Identity/role
resolution and selecting the requested page are separate fixed-cost operations.

After `ANALYZE` on the 1,000-post fixture, the latest-topic query plan included:

```text
Limit (rows=20)
  Sort (rows=1000; authored_at DESC, id)
    Merge Anti Join (removed/rejected inclusion exclusion)
      Nested Loop
        Index Scan on communities_id_federation_mode_key
        Hash Join
          Seq Scan on posts (parent_id IS NULL, deleted_at IS NULL)
          Seq Scan on site_posts (site_id, hidden_at IS NULL)
```

The plan also used indexed membership/manager lookups. This fixture did not
justify a new index or schema migration. It verifies query structure and bounded
round trips, not a production latency guarantee. These are local HTTP/database
acceptance results; they do not claim new live peer interoperability evidence.

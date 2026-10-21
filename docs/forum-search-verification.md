# Forum search verification

## Integrated verification (2026-10-21)

The integrated workspace passes `make build test test-postgres`, including
migrations, route dispatch, normalized rich-content writes, and notification
projection. Reproduce the focused plan and query-count checks with:

```sh
ulimit -v 8000000
export GOCACHE=/tmp/commune-participation-gocache
export GOMODCACHE=/tmp/commune-mygo-modcache
timeout 120 bash scripts/test-postgres.sh -run 'TestPostgres(Search|NotificationsQueryPlan|BrowserBatchQueries)' -v
```

All four selected tests passed. Search post enrichment used 3 queries for both
1 and 20 results; the broader browser fixture used 4 for both sizes. Counts
exclude viewer resolution and the search query, and remain independent of page
size. Rich remote metadata may require one additional batched cache lookup.
Notification pages of 1, 20 and 50 used 2 selects each, with no enrichment query.

The 1000-post search fixture chose Limit/Sort/Hash Anti Join/Hash Join and
sequential scans with literal Chinese ILIKE predicates (estimated top cost
119.54..119.59). The notification fixture contained 2000 posts and 1000 mentions;
after reception revocation and reply/mention precedence, 1500 notifications were
visible. EXPLAIN (ANALYZE, BUFFERS) reported 65.355 ms for a 20-row page and
59.783 ms for unread count on this run. Its principal nodes were nested loops,
hash joins, and the existing notification event/account unique index. These
small local fixtures are correctness and plan evidence, not production latency
guarantees. No new extension or speculative index is required.

The following isolated results are historical; their query counts and integration
limitations have been superseded by the integrated verification above.

## Integration contract

Call `SearchRoute(settings, db, site, w, request, parts)` before existing browser
read/mutation dispatch and return when it returns true. This implements
`GET /api/v1/search?kind=posts|communities&q=...&limit=...&offset=...`.
Search accepts 1–200 Unicode code points, rejects whitespace-only/invalid UTF-8/NUL
queries, and preserves query spaces and punctuation literally.

The main agent owns the additive `posts.search_text text NOT NULL DEFAULT ''`
migration and backfill. The rich-content writer must atomically maintain this
column from decoded visible rendered text on publish, edit, remote receive/update,
and deletion. Do not store escaped HTML or Markdown source: link destinations,
tags, attributes, and discarded script/style content must not become searchable.
Repository tests explicitly supply normalized text; they do not prove renderer
or migration integration. Existing plain title fields are searched separately.

Search reuses the readable-community CTE. Post reception, hidden/deleted state,
and removed/rejected inclusion are filtered before offset/limit. Replies are
searchable as posts. Communities must be hosted here or have a currently visible
received post here. Community searches audit returned administrative reads;
post HTTP searches use BrowserPosts for batch enrichment and read auditing.

## Verified evidence

Parallel in-progress config/content files prevented workspace-wide MyGO sync.
An isolated HEAD checkout at `/tmp/commune-search-validation` plus the four new
search MyGO files was generated with `/tmp/commune-mygo-build/mygo sync`, storage
before server. No generated Go was edited manually.

An isolated PostgreSQL 18.6 cluster under `/tmp/commune-search-pg` ran:

```sh
ulimit -v 4194304
export GOCACHE=/tmp/commune-search-gocache
export GOMODCACHE=/tmp/commune-mygo-modcache
export COMMUNE_TEST_POSTGRES_DSN='host=/tmp/commune-search-pg/socket port=55447 user=commune_test dbname=postgres sslmode=disable connect_timeout=5'
timeout 120 go test ./internal/storage ./internal/server -run 'Test(Search|PostgresSearch)' -count=1 -v
```

All three tests passed: TestSearchValidation, TestPostgresSearch, and
TestPostgresSearchRoute. Storage/server package times were 0.347s/0.358s.
Coverage includes Chinese/case-insensitive matching, literal `%`, `_`, backslash
and quote, normalized text rather than source, stable ties/offsets, private and
blocked readers, absent site reception, hidden/rejected/deleted posts, updated
text, administrative community audits, validation, no-store, empty arrays, 405,
503 on broken storage, and enriched post HTTP output.

On 1000 fixture posts, post enrichment used **2 queries for 1 result and 2 queries
for 20 results**, with an anonymous reader. Administrative audit adds at most one
batch insert. This count excludes viewer resolution and the search query.

After ANALYZE of posts, site_posts and communities, EXPLAIN for a 20-row Chinese
search produced the following principal nodes (full output is reproducible from
TestPostgresSearch; temporary run log: `/tmp/commune-search-results.log`):

```text
Limit (cost=118.54..118.59 rows=20 width=199)
  Sort (cost=118.54..119.79 rows=500 width=199)
    Sort Key: p.authored_at DESC, p.id
    Hash Anti Join (posts versus removed/rejected collection memberships)
      Hash Join (posts versus site_posts)
        Hash Join (posts versus readable communities)
          Seq Scan on posts (deleted_at + literal title/search_text ILIKE)
          Seq Scan on communities (shared read-policy predicate)
        Seq Scan on site_posts (site_id + hidden_at)
      Seq Scan on collection_memberships (removed/rejected)
```

This is an EXPLAIN estimate, not a measured production latency benchmark.
A broad matching query on this small fixture chooses sequential scans and hash
joins. No index or extension was added; these data do not justify requiring
pg_trgm. Reassess with production-scale selective workloads before indexing.

Direct SQL fixtures must populate search_text or use the normalized writer;
falling back to raw body would violate markup-free search. Independent process
and external peer acceptance are tracked separately in the change tasks.

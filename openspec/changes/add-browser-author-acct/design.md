## Context

See [`proposal.md`](proposal.md) for motivation and [`specs/`](specs/) for observable contracts.

Current constraints:

- Browser post output is built in [`PostDTO()`](../../../../internal/server/forum.mygo:75) and enriched in [`BrowserPosts()`](../../../../internal/server/browser_output.mygo:71). The only author field is `author_actor_uri`.
- [`LoadPostRichStates()`](../../../../internal/storage/post_content.mygo:36) already performs one batched query for a whole page and is the natural place to add author metadata without increasing query count.
- Local usernames live in `accounts`; display names live in `profiles`. The `actors` table has no handle column.
- Remote posts arrive through [`PostRepository.Receive()`](../../../../internal/storage/posts.mygo:49) inside federation transactions. [`EnsureRemoteActor()`](../../../../internal/storage/context_backfill.mygo:6) creates remote Actors before reception.
- [`federation.Fetch()`](../../../../internal/federation/fetch.mygo:93) already enforces HTTPS, private-address blocking, byte/time limits, and per-hop redirect validation, but sends a fixed ActivityPub `Accept` header.
- [`StartParticipationWorkers()`](../../../../internal/server/participation_workers.mygo:86) provides durable leased workers coordinated by PostgreSQL.
- The browser enrichment tests require page-size-independent query counts, so author data must not trigger per-post queries.

## Goals / Non-Goals

**Goals:**

- Add a verified `acct` and an ActivityPub `name` projection to the browser author contract.
- Keep browser reads free of network I/O and free of per-post author queries.
- Make remote handle resolution restartable, retryable, block-aware, and bounded by the existing federation fetch policy.
- Keep `author_actor_uri` as the only identity used for authorization and editing.
- Preserve existing browser and mutation payload compatibility.

**Non-Goals:**

- Backfill handles for every historical remote Actor. Resolution is enqueued when a remote Person author is newly encountered or reappears in received content.
- Resolve remote handles synchronously or return a freshly resolved handle in the same request that first discovers the author.
- Support handle discovery for non-Author actors such as remote Group managers or roster-only actors.
- Download or cache remote avatars or biographies during handle resolution.
- Change the existing Person `Update` signature, freshness, or delivery rules.

## Decisions

### 1. Store remote handles in `actors.acct`; compute local handles

Add an additive migration `014_actor_handles.sql`:

```sql
ALTER TABLE actors ADD COLUMN acct text NOT NULL DEFAULT '';
```

Local handles are derived at read time from `accounts.username` and `sites.canonical_origin`. Storing them would duplicate data that is already authoritative and could become stale if site provisioning changes. Remote handles are stored because there is no local account row and WebFinger is the only authoritative source.

Alternatives considered:

- Store local handles too: rejected because the account and canonical site origin already define them.
- Store a separate `preferred_username` column: rejected because `preferredUsername` is not the complete handle; the verified WebFinger domain is required.
- Store a per-site handle: rejected because a handle belongs to the Actor, not the observing site. Only the resolution job is site-scoped for block checks.

### 2. Persist a site-scoped resolution job

Add:

```sql
CREATE TABLE actor_handle_jobs (
    site_id text NOT NULL REFERENCES sites(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    state text NOT NULL DEFAULT 'pending'
        CHECK (state IN ('pending','leased','done','failed','suppressed')),
    attempts int NOT NULL DEFAULT 0,
    available_at timestamptz NOT NULL DEFAULT now(),
    lease_token text,
    lease_until timestamptz,
    error_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, actor_uri)
);
```

The primary key makes enqueue idempotent. The site dimension allows the worker to recheck the receiving site's actor/domain block policy. A successful resolution updates the global `actors.acct`, so other sites benefit without another fetch.

Claiming follows the existing delivery-job pattern: `FOR UPDATE SKIP LOCKED`, lease token, lease expiry, ordered by `available_at`, bounded batch size. Jobs with an expired lease are reclaimable.

### 3. Enqueue inside accepted remote post reception

Call a new storage helper from [`PostRepository.Receive()`](../../../../internal/storage/posts.mygo:49) after the post row is accepted:

```text
QueueActorHandleResolution(ctx, tx, siteID, authorActorURI)
```

The helper:

1. Loads the Actor row.
2. Does nothing for a missing actor, a local actor (`local_site_id` non-null), a non-Person actor, or a non-empty `acct`.
3. Inserts `(site_id, actor_uri)` with `ON CONFLICT DO NOTHING`.

`Receive` is the right boundary because it already runs inside the federation transaction that accepted the author's content and has the receiving site ID. Local publication uses a different repository path and does not enqueue.

This deliberately does not perform a write on browser GET. A stale remote Actor that never appears in new content remains unresolved and displays the fallback.

### 4. Resolve through Actor document plus WebFinger

The worker performs a two-step public discovery:

```text
Actor URI
   │  GET with Accept: application/activity+json
   ▼
Actor document
   │  require id == Actor URI
   │  require type == "Person"
   │  require non-empty preferredUsername
   │  optionally read name and updated
   ▼
WebFinger resource acct:<preferredUsername>@<actor authority>
   │  GET with Accept: application/jrd+json
   ▼
JRD document
   │  require subject == candidate account
   │  require exactly one rel="self" ActivityPub link
   │  require self.href == Actor URI
   ▼
acct = subject without "acct:"
```

The Actor URI authority is used only as the WebFinger endpoint. It is never used to construct the displayed handle. The displayed domain comes from the verified WebFinger `subject`; if the remote uses an unrelated handle domain and its Actor authority cannot resolve it, the handle remains empty.

[`federation.Fetch()`](../../../../internal/federation/fetch.mygo:93) currently fixes the `Accept` header. Add a private/public fetch variant that accepts an explicit `Accept` value while reusing `FetchBounded`. `Fetch` delegates to it with the ActivityPub type so existing callers do not change. WebFinger uses `application/jrd+json`.

Validation mirrors the mention discovery path:

- Reject non-200 responses and duplicate JSON keys.
- Require `WantsActivityJSON` for the Actor document.
- Require the JRD content type or a JSON-compatible response for WebFinger.
- Enforce the existing timeout, byte, redirect, HTTPS, and destination rules.
- Limit WebFinger response bytes more tightly than the general fetch limit.

### 5. Bootstrap blank remote display names without weakening authority

When the Actor document fetch succeeds and its `id` matches the stored Actor URI, the worker may fill a blank remote profile display name from ActivityPub `name`.

```sql
INSERT INTO profiles(actor_uri, display_name, updated_at)
VALUES (?, ?, coalesce(?, to_timestamp(0)))
ON CONFLICT (actor_uri) DO UPDATE
SET display_name = EXCLUDED.display_name
WHERE profiles.display_name = ''
```

Rules:

- Never update a local profile.
- Never overwrite a non-empty display name.
- Do not advance `profiles.updated_at` on conflict, so a later signed Person update with a real timestamp is not blocked.
- Apply `content.RenderText` to the ActivityPub `name` before storage.
- Do not store `summary`, `icon`, or any avatar bytes during this bootstrap.

The alternative was to only resolve `acct` and leave `display_name` empty until a Person `Update`. That would not meet the browser author contract for newly encountered remote authors and would keep many display names blank indefinitely.

### 6. Extend the existing batched author lookup

Extend `PostRichState` with:

- `AuthorUsername`
- `AuthorOrigin`
- `AuthorAcct`
- `AuthorDisplayName`

Extend the existing [`LoadPostRichStates()`](../../../../internal/storage/post_content.mygo:36) query with correlated subqueries or left joins for `accounts`, `sites`, `actors.acct`, and `profiles.display_name`. The query remains one batch query per page.

`BrowserPosts` computes:

```text
acct =
    local origin and username present
        ? username + "@" + normalized authority(origin)
        : actors.acct
```

Then it populates a new `AuthorOutput` on `PostOutput`. `PostDTO` gains an author argument or a helper applies the author fields after DTO creation. All browser post routes already pass through `BrowserPosts`, so no route-specific duplication is needed.

Alternatives considered:

- Add a separate batch author query: rejected because the enrichment query budget is deliberately tight and page-size independent.
- Join author data into list queries directly: rejected because `BrowserPosts` is the single projection point for lists, detail, search, and mutation responses.

### 7. Worker configuration and lifecycle

Add `actor_workers` under `participation_workers`:

- Default `1`.
- Range `1..32`.
- `0` is normalized to the default, matching existing worker fields.
- Validated with the other participation-worker settings.

Add an `"actor_handles"` worker kind to `ParticipationBatch` and `StartParticipationWorkers`. The worker uses the existing `LeaseSeconds`, `MaxAttempts`, `RetryBaseSeconds`, `RetryMaxSeconds`, `BatchSize`, and `PollIntervalSeconds` settings and exits with the server lifetime context.

Retry classification:

| Outcome | Action |
| --- | --- |
| Success and verified handle | `done` |
| Transport error, timeout, 5xx, temporary DNS failure | retry with bounded backoff |
| 404, invalid document, identity mismatch, no matching self link | retry until attempts exhausted, then `failed` |
| Site block or domain block | `suppressed` without a request |
| Actor already has `acct` | `done` without a request |
| Local or non-Person actor | `suppressed` |

No worker path enqueues another resolution job.

### 8. Block and privacy checks

Before fetching, the worker loads the receiving site's policy and checks the actor URI and its authority against the existing site block tables. A blocked job is suppressed with no remote request and no content disclosure.

Resolution only fetches an Actor URI already stored by verified inbound processing. It does not accept a client-supplied URL at job time. The fetched Actor and WebFinger documents are public metadata; private protected content is out of scope. The worker does not log post bodies, credentials, private keys, or protected content.

## Risks / Trade-offs

- **Custom handle domains may remain unresolved** → The Actor authority is the only standard WebFinger starting point without a known handle. Leave `acct` empty rather than guess; the fallback remains usable.
- **First browser read may still show an empty handle** → Resolution is asynchronous. UI falls back to `display_name` or `author_actor_uri`, and the next refresh shows the result.
- **Existing remote actors are not mass-backfilled** → Avoids unbounded outbound fetch on deployment. Actors are enqueued when they reappear in newly received content. A later bounded reconciliation job can be added without changing the API.
- **Public Actor document bootstrap is not signature-verified** → Require HTTPS, canonical Actor `id`, and bounded fetch; only fill blank display names and never overwrite verified data or use the name for authorization.
- **A remote peer can be slow or unavailable** → Leases, bounded batch size, fetch timeouts, retry limits, and one-job-at-a-time failure isolation prevent a single peer from blocking all work.
- **`actors.acct` can become stale if a remote actor changes its handle** → Person updates currently carry `preferredUsername`; a later enhancement can refresh stored handles using the same verification path. The current change treats the stored handle as display metadata and never as identity.
- **Query-plan regression from extra author subqueries** → Reuse the existing batched statement, add representative PostgreSQL plan checks, and keep the existing page-size-independent query-count test.

## Migration Plan

1. Add migration `014_actor_handles.sql` with `actors.acct` and `actor_handle_jobs`; register it in the migration catalog.
2. Deploy the additive schema and the backend that reads `author`. Existing clients ignore the new fields.
3. Add the `actor_workers` configuration with a safe default; leave resolution disabled only if operators set participation workers off.
4. Deploy the frontend decoder and author display. It accepts missing `author` by falling back to `author_actor_uri`.
5. Roll back by disabling worker kinds first and restoring the previous executable only after confirming migration compatibility. Keep the additive column and job table; dropping them is unnecessary and could lose resolved handles.

No existing rows are rewritten. Remote `acct` values start empty and fill incrementally.

## Open Questions

None that change the specs or task breakdown. The unresolved-remote-handle behavior is explicitly specified as an empty string and a client fallback.

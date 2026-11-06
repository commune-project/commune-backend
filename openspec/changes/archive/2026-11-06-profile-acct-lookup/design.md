## Context

See `proposal.md` for motivation and `specs/user-profiles/spec.md` for the
behavior contract. Profiles are keyed by Actor URI. Local identity lives in
`accounts(site_id, username)` with a unique pair per site. `actors` already has an
`acct` column, populated only for verified remote handles; a remote Actor is
`kind='Person'` with `local_site_id IS NULL`. `site_authorities` maps routing
authorities to sites, so a handle domain can be matched to a configured site.

`PublicProfile` currently joins `accounts` and then `profiles`; it has no remote or
cross-site path and no block checks. `mention_candidates` already unions current-site
accounts, other-site accounts, and stored remote handles with block filtering.
`DiscoverMentionActor` performs the exact handle-to-Actor verification needed here:
WebFinger subject match, single ActivityPub self link, Actor identity/type/username
checks, canonical inbox, no redirects, site block checks, and a 64 KiB cap.

`actor_handle_jobs` is keyed by `(site_id, actor_uri)` with a foreign key to
`actors(uri)`, and its worker resolves an Actor document back to a verified handle.
Today it only bootstraps a blank display name and never stores biography or avatar.

## Goals / Non-Goals

**Goals:**

- Handle-based reads across current-site accounts, other configured sites, and stored
  remote Persons with one deterministic resolution order.
- One authenticated, rate-limited resolve trigger that uses existing bounded fetch
  policy.
- Idempotent persistence shared by the trigger and background read-path bootstrap.
- Block and ban visibility consistent with mention candidates.

**Non-Goals:**

- A user/actor search endpoint or autocomplete expansion.
- Periodic remote profile refresh, avatar download, proxy, or cache.
- Changing ActivityPub Person representations or delivery.
- Resolving handles from the local part alone for remote domains.
- Backfilling profiles for every historical actor in one migration.

## Decisions

### Resolution order is local authority first, stored handle second

A handle is split into exactly one local part and one domain. The domain is compared
against configured site authorities, including aliases and non-default ports; a match
uses the local account of that site and never performs network discovery. Without a
match, the handle is compared case-insensitively against `actors.acct` for remote
Persons. Local authority wins if both could match, which keeps WebFinger's own
precedence and avoids a stored remote handle shadowing a local account.

The lookup is one SQL statement with a union of candidate sources and an explicit
source rank, mirroring `mention_candidates`. This avoids an N+1 sequence and makes
the precedence testable. Alternatives considered: separate queries with early return,
which is simpler but duplicates block logic and makes race behavior harder to reason
about.

### Visibility reuses site policy and does not leak the reason

Site actor blocks, site domain blocks, and active site bans are applied in SQL. When a
valid session exists, the viewer's person and instance blocks are applied as well.
Every rejection returns `404`. An unauthenticated read cannot evaluate personal blocks
and does not attempt to.

### The response adds `acct` and keeps `username` local-only

The projection adds `acct`, derived from the account and canonical origin for local
accounts and from the stored handle for remote Persons. `username` remains empty for
remote Persons so clients cannot mistake a remote local part for a current-site
account. `actor_uri` remains the canonical link target. This is additive; existing
JSON consumers keep working.

### `resolve=1` is a synchronous, authenticated pull

The trigger requires a current-site session because an unauthenticated endpoint that
fetches arbitrary domains is an SSRF amplifier. It reuses the generalized
`DiscoverMentionActor` path: no redirects, site block check before every request,
existing federation timeout and byte limits, and no media fetch. Configured-site
domains short-circuit to the local account path and perform no network request.

Rate limiting is database-backed so it survives restarts and works across in-process
workers. A small `profile_resolve_limits(site_id, account_id, window_start, attempts)`
table is upserted atomically; expired windows are replaced. Limits live under
`federation.profile_resolve_limit` (default 20) and
`federation.profile_resolve_window_seconds` (default 3600), defaulted alongside the
existing participation defaults and validated with bounded ranges.

Status mapping is deliberate: `401` unauthenticated, `404` unverifiable handle,
`429` rate limited, `503` peer unavailable within limits. The distinction lets a
client retry transient failures without exposing whether an unverifiable account
exists.

### Bootstrap persists only empty fields and never advances freshness

Both interactive resolution and background bootstrap use one upsert:

- Insert the Actor with `kind='Person'`, `inbox_uri`, and the verified handle when it
  does not exist.
- Fill `acct` only when the stored value is empty; never replace a different verified
  handle from this path.
- Insert a profile row with `updated_at` set to the Actor document timestamp when
  present, otherwise the epoch, so any later verified Person Update wins.
- On conflict, fill only empty `display_name`, `biography`, `biography_html`, and
  `avatar_url` fields and leave `updated_at` unchanged.

This mirrors `BootstrapRemoteDisplayName` and satisfies both “persist the lookup” and
“do not overwrite authoritative data”. Markup is sanitized through the configured
rich-content sanitizer; avatar URLs are validated as HTTPS metadata and never fetched.

### Background bootstrap reuses the actor handle worker

Read paths enqueue `actor_handle_jobs` with `ON CONFLICT DO NOTHING`, so duplicate
lookups collapse per site and the existing lease/backoff machinery applies. The
worker’s resolved handle grows biography, avatar, and update timestamp fields, and on
success calls the same bootstrap upsert.

Enqueue points are bounded: post search results enqueue at most the authors present in
the returned page, mention candidates at most the returned items, and received posts
enqueue their author after the accepting transaction commits. Responses are computed
from existing rows and never wait for the job. If participation workers are disabled,
jobs remain pending; `resolve=1` still works interactively.

### Index

Add a partial expression index for the remote branch:

```sql
CREATE INDEX actors_acct_person_lower
    ON actors (lower(acct))
    WHERE acct <> '' AND kind = 'Person' AND local_site_id IS NULL;
```

Local lookups already use the `accounts(site_id, username)` unique index.

## Risks / Trade-offs

- **Cross-site identity disclosure** → Profiles are public by design, and `404` is
  uniform for disabled, blocked, and missing resources. No email or credential field
  enters the projection.
- **Handle collision** → Local authority precedence is specified and covered by a test.
- **Read-path write amplification** → Enqueue is bounded to returned items, uses
  `ON CONFLICT DO NOTHING`, and is backed by the existing ready-job index.
- **Rate-limit table growth** → Rows are keyed by a truncated window and can be pruned
  by the same worker loop; the design keeps the window bounded.
- **Worker disabled or backed up** → Background fields stay empty, but explicit
  `resolve=1` remains functional; the limitation is documented.
- **Handle changes upstream** → A verified handle already stored is not replaced by a
  background lookup, avoiding identity churn; a later authoritative Actor update can
  still change profile fields.
- **Stored remote profile may be sparse** → The projection returns empty strings rather
  than null, consistent with existing profile output.

## Migration Plan

Add one migration for the expression index and the resolve rate-limit table, and
register it in the migration catalog. No data backfill runs. Deploy the binary after
migration; old binaries ignore the new table and index. Rollback leaves the additive
schema in place. After deployment, verify a bare username, a current-site handle, a
handle for another configured site, a stored remote handle, `resolve=1` failure modes,
and a block-hidden profile.

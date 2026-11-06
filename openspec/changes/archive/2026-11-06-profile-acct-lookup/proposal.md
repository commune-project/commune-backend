## Why

Public profiles can only be read by exact username within the requesting site.
Remote Person profiles already stored in `actors` and `profiles` cannot be read
through the browser API, other configured sites' local accounts are invisible, and
read paths such as search results and received posts can show a remote author with
no stored profile at all.

## What Changes

- Extend `GET /api/v1/profiles/{acct}` so a path segment without `@` keeps the
  current-site username lookup, while a `username@domain` handle resolves first to a
  local account of a configured site authority and otherwise to a stored remote
  Person by verified handle.
- Add an `acct` field to the public profile response. `username` remains the local
  account name and stays empty for remote Persons; `actor_uri` remains the canonical
  identity.
- Apply site actor/domain blocks and active site bans to profile reads, and apply
  the viewer's personal person/instance blocks when a valid session is present.
  Disabled accounts and missing or blocked profiles return `404`.
- Add `?resolve=1` to the same endpoint for a missing remote handle. Resolution
  requires authentication, is rate limited, applies only to domains that are not a
  configured site authority, performs no redirects, and uses the existing bounded
  federation fetch limits. Success returns the stored profile; failure returns `404`;
  an unreachable peer returns `503`.
- Persist every successful lookup as an idempotent upsert of the verified handle and
  profile fields. Existing newer profile data SHALL NOT be overwritten.
- Trigger the same background profile bootstrap when other read paths encounter a
  stored remote Person without a profile, including post search results, mention
  candidates, and authors of received posts. These paths SHALL enqueue work without
  performing network discovery inline and without changing their response shape.
- Add a partial expression index on `lower(acct)` for remote Person actors.
- Document the handle lookup, cross-site behavior, resolve trigger, and background
  bootstrap in `docs/participation-api.md`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `user-profiles`: public profile reads accept handles, cover remote and other-site
  Persons, apply block visibility, support an authenticated resolve trigger, and
  persist bootstrapped remote profiles from explicit and background lookups.

## Impact

- Browser route and projection in `internal/server/profiles.mygo`.
- Storage queries in `internal/storage/profiles.mygo`, `internal/storage/mention_candidates.mygo`,
  and the existing actor handle bootstrap in `internal/storage/actor_handles.mygo`.
- Actor discovery in `internal/server/post_mentions.mygo` is generalized for handle lookup.
- New migration under `internal/migrationfiles/migrations/` and catalog registration.
- No change to ActivityPub representations, delivery, or stored post content.
- Asynchronous bootstrap reuses the existing actor handling worker; read paths do not
  block on federation traffic.

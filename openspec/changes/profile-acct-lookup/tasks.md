## 1. Storage and schema

- [ ] 1.1 Add migration `023_profile_handle_lookup.sql` with the partial `actors(lower(acct))` index and the `profile_resolve_limits` table, register it in the migration catalog, and verify an upgrade from the current head succeeds.
- [ ] 1.2 Add a handle-based profile query that ranks configured-site local accounts ahead of stored remote Persons and applies site actor blocks, site domain blocks, and active site bans; verify with at least one candidate per source and a local-over-remote collision case.
- [ ] 1.3 Add the `acct` projection field, keep `username` empty for remote Persons, and verify the JSON shape for local, other-site, and remote profiles.
- [ ] 1.4 Add `federation.profile_resolve_limit` and `profile_resolve_window_seconds` with defaults and bounded validation, and verify omitted values default while out-of-range values fail.
- [ ] 1.5 Add an atomic rate-limit upsert and rollback on rejection, and verify the limit is shared across callers and resets after the window.

## 2. Interactive resolution

- [ ] 2.1 Generalize the existing mention discovery into a reusable verified handle lookup returning Actor URI, inbox, handle, biography, avatar, and update timestamp; verify the existing mention tests still pass.
- [ ] 2.2 Wire `?resolve=1` into the profile route with current-site authentication, configured-site short-circuit, and `401`/`404`/`429`/`503` mapping; verify each status with a fake fetcher.
- [ ] 2.3 Implement the bootstrap upsert that inserts the Actor and fills only empty profile fields without advancing `updated_at`; verify a later authoritative Person Update still wins.
- [ ] 2.4 Verify a successful resolve stores the handle and profile fields so a subsequent read without `resolve=1` hits the database only.

## 3. Background bootstrap

- [ ] 3.1 Extend actor handle job enqueueing to cover a stored remote Person with a missing profile, while preserving the one-pending-job-per-site guarantee.
- [ ] 3.2 Extend the resolved handle payload and worker success path to persist biography, sanitized biography HTML, avatar metadata, handle, and timestamp through the bootstrap upsert.
- [ ] 3.3 Enqueue bootstrap from post search results, mention candidates, and received post acceptance without changing response bodies or blocking on federation traffic.
- [ ] 3.4 Verify duplicate lookups enqueue once, the worker remains idempotent, and disabled workers leave read responses unchanged.

## 4. Documentation and verification

- [ ] 4.1 Document bare-username versus handle lookup, cross-site precedence, block visibility, `resolve=1` authentication and status codes, rate limiting, and background bootstrap in `docs/participation-api.md`.
- [ ] 4.2 Bootstrap-sync packages in dependency order (`storage`, then `federation`, then `server`) and verify `go test -run '^$'` compiles every affected package.
- [ ] 4.3 Run focused storage, server, and migration tests for handle lookup, resolution, rate limiting, and bootstrap and verify all pass against an isolated PostgreSQL instance.
- [ ] 4.4 Run `openspec validate profile-acct-lookup --strict` and verify it passes.

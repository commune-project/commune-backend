## 1. Schema and shared foundations

- [ ] 1.1 Add `015_votes.sql` with the reaction `score` column, its check constraint, and the `Dislike` activity kind; verify migration on a fresh database and on a database containing existing reactions.
- [ ] 1.2 Add `016_password_reset.sql` with reset tokens, reset mail jobs, and reset rate limits; verify constraints, indexes, and cascade behavior with migration tests.
- [ ] 1.3 Add `017_community_follows.sql` with a `follow_policy` column, a backfill of existing members-only communities to `members`, and indexes for accepted follower counts and pending follow review; verify the backfill, query plans, and existing follow tests.
- [ ] 1.4 Add `018_account_blocks.sql` with person, community, and instance block rows; verify primary keys, site/account foreign keys, and duplicate-block behavior.
- [ ] 1.5 Add `019_moderation.sql` with reports, moderation log entries, community bans, and site bans; verify the partial unique open-report index and the append-only log trigger.
- [ ] 1.6 Add `020_saved_read_state.sql` with saved, read, and personal-hidden rows; verify per-account uniqueness and post foreign keys.
- [ ] 1.7 Add `021_notification_targets.sql` making notification post targets nullable and adding target kind and identifier; verify existing rows backfill as post targets.
- [ ] 1.8 Register every new migration in the migration catalog and verify `make test-postgres` applies them in order on a fresh cluster.
- [ ] 1.9 Add a shared personal-block SQL predicate or CTE builder; verify it with person, community, and instance cases in a storage test.
- [ ] 1.10 Add shared parsers for vote values, sort modes, thread depth, block kinds, report states, and ban expiry; verify invalid values return `400`.
- [ ] 1.11 Add shared pagination and visibility helpers for the new account and moderation listings; verify malformed and exhausted pages.
- [ ] 1.12 Add `022_site_vote_settings.sql` with one row per site, default-true upvote/downvote booleans, update metadata, and an actor reference; verify defaults, constraints, and provisioning upserts.
- [ ] 1.13 Implement a site vote settings repository with read and partial-update operations; verify missing-row defaults, site isolation, and audit writes.
- [ ] 1.14 Implement `GET /api/v1/site/vote-settings` and `PUT /api/v1/admin/vote-settings` with site-admin/deployment authority, validation, CSRF, and no-store responses.
- [ ] 1.15 Add a shared disabled-feature error mapping and a vote-direction gate helper; verify stable `403 feature_disabled` behavior.
- [ ] 1.16 Seed vote settings during site provisioning and verify existing sites without a row still resolve both directions as enabled.
- [ ] 1.17 Add HTTP and storage tests for site A disabling downvotes while site B remains enabled, partial updates, and unauthorized updates.

## 2. Personal blocking

- [ ] 2.1 Implement the account-block repository with list, add, and remove operations; verify idempotency, self-block rejection, and site scoping in unit tests.
- [ ] 2.2 Implement `GET/POST/DELETE /api/v1/account/blocks` with session, origin, CSRF, and error mappings; verify authenticated and anonymous HTTP cases.
- [ ] 2.3 Apply personal blocks to community discovery and latest topics; verify blocked authors, communities, and instances do not consume page slots.
- [ ] 2.4 Apply personal blocks to community topic lists and post detail; verify excluded IDs return `404` without metadata.
- [ ] 2.5 Apply personal blocks to the unified threaded reply read; verify a blocked author's subtree is omitted and visible child counts exclude it.
- [ ] 2.6 Apply personal blocks to search results and counts; verify blocked posts and communities are filtered before pagination.
- [ ] 2.7 Apply personal blocks to notification listing, unread counts, saved/read/liked lists, and community discovery counts.
- [ ] 2.8 Enforce blocked interaction eligibility for replies, votes, and mentions; verify rejected requests create no content, vote, mention, or notification.
- [ ] 2.9 Add block-aware storage and HTTP tests covering a block created before and after the target content is read.
- [ ] 2.10 Document personal blocks and their separation from site-administrator policy in `docs/permissions.md`; verify the documented paths match the routes.

## 3. Votes and ranking

- [ ] 3.1 Extend the reaction repository to set, change, and clear vote scores; verify one active vote per actor and unchanged legacy like behavior.
- [ ] 3.2 Add `score`, `upvotes`, `downvotes`, `voted_by_me`, compatibility `like_count`, and `can_upvote`/`can_downvote` to the post projection; verify list, detail, search, and mutation responses.
- [ ] 3.3 Implement `POST /api/v1/posts/{id}/vote` with validation, current access checks, and the resolved site's vote-direction gate; verify `204`, `400`, `401`, `403 feature_disabled`, and `404` cases.
- [ ] 3.4 Keep `POST/DELETE /api/v1/posts/{id}/likes` as upvote/clear aliases; verify both paths converge on the same reaction state.
- [ ] 3.5 Implement `top`, `hot`, and `controversial` ordering for latest and community topic lists; verify disabled directions are excluded from score and score changes affect the next page.
- [ ] 3.6 Implement vote-aware ordering for the unified threaded reply read; verify sibling order and stable tie-breaking.
- [ ] 3.7 Add inbound `Dislike` parsing and outbound `Dislike` delivery; verify signature checks, idempotent replay, local-only exclusion, and disabled-direction no-op receipts.
- [ ] 3.8 Update `docs/federation.md` and `docs/api.md` with vote and `Dislike` behavior; verify examples and status codes match tests.
- [ ] 3.9 Add site vote settings API acceptance for disable, re-enable, historical vote restoration, and cross-site isolation.

## 4. Comment threads

- [ ] 4.1 Implement one bounded recursive reply query with root pagination and recursive children; verify one-level, multi-level, and empty threads.
- [ ] 4.2 Add the unified response with recursive `children`, `depth`, and `child_count` to root `items`; verify no separate flat query or response path exists.
- [ ] 4.3 Enforce `max_depth` bounds and default; verify `1`, `8`, invalid, and deeper-than-limit requests.
- [ ] 4.4 Implement `new`, `old`, `top`, and `controversial` sibling ordering with `old` as the default; verify each level is ordered independently and the existing root order is preserved.
- [ ] 4.5 Enforce reception, read, deletion, hiding, inclusion, and personal-block inheritance; verify hidden parents suppress descendants.
- [ ] 4.6 Extend reply route dispatch so absent/view=tree/view=flat all use the unified query and `view=flat` only sets `max_depth=1`; verify method and query errors.
- [ ] 4.7 Add HTTP acceptance for a three-level thread, a shallow `max_depth=1` page, a blocked subtree, and a hidden parent; verify no excluded body or count leaks.
- [ ] 4.8 Document the unified response, `old` default, and `view=flat` alias in `docs/forum-browser-api.md`; verify the documented shape matches the DTO.

## 5. Saved, read, hidden, and liked state

- [ ] 5.1 Implement saved, read, and personal-hidden repositories with idempotent set/clear operations; verify per-account isolation.
- [ ] 5.2 Implement `POST/DELETE /api/v1/posts/{id}/save` and verify unreadable, deleted, hidden, and duplicate cases.
- [ ] 5.3 Implement `POST /api/v1/posts/{id}/read` and verify idempotent read records for readable posts.
- [ ] 5.4 Implement `POST/DELETE /api/v1/posts/{id}/hide-for-me` and verify it never changes `site_posts.hidden_at`.
- [ ] 5.5 Implement `GET /api/v1/account/saved`, `/read`, `/hidden`, and `/liked` with current-access rechecks and pagination.
- [ ] 5.6 Add `saved_by_me`, `read_by_me`, `hidden_by_me`, `can_save`, and `can_hide_for_me` to post responses; verify anonymous and authenticated views.
- [ ] 5.7 Filter personally hidden posts from latest, community, search, saved, read, and liked feeds while keeping direct detail behavior.
- [ ] 5.8 Add HTTP acceptance for saved/read/hidden/liked isolation and access revocation; verify excluded content does not leak.
- [ ] 5.9 Document account content-state endpoints in `docs/forum-browser-api.md`; verify examples and error mappings.

## 6. Community follows

- [ ] 6.1 Implement the community `follow_policy` transitions for `open`, `members`, `approval`, and `disabled`; verify accepted, pending, rejected, and undone rows.
- [ ] 6.2 Implement `POST/DELETE /api/v1/communities/{id}/follow` with session, origin, CSRF, and community access checks.
- [ ] 6.3 Implement pending follow review and decision routes; verify manager-only access, idempotency, audit rows, and review of existing pending rows after a policy change.
- [ ] 6.4 Make `approval` follow approval atomically approve membership and follow; verify rejection creates no membership and `members`/`disabled` create no pending rows.
- [ ] 6.5 Add `follow_policy`, `viewer.is_following`, `viewer.follow_state`, `viewer.can_follow`, and `follower_count` to community responses; verify anonymous and restricted visibility.
- [ ] 6.6 Extend `PUT /api/v1/communities/{id}/policy` with optional `follow_policy`; verify manager-only access, validation, audit, and preservation of existing follows.
- [ ] 6.7 Extend the community route dispatcher to the six-segment follow-decision path; verify existing member and policy routes still work.
- [ ] 6.8 Queue and consume federated `Follow`, `Undo`, `Accept`, and `Reject` according to the hosted policy; verify replay does not duplicate or undo a newer follow.
- [ ] 6.9 Add follow HTTP and federation acceptance for open, members, approval, disabled, local-only, and replayed follows.
- [ ] 6.10 Document follow policy, pending review, and membership interaction in `docs/api.md` and `docs/federation.md`.
- [ ] 6.11 Extend community creation with an optional `follow_policy` and derive the default from read policy; verify created, omitted, and invalid values.

## 7. Password reset and change

- [ ] 7.1 Add reset token generation, digest, encryption, and opening helpers with a reset-specific associated-data label; verify round-trip and tamper rejection.
- [ ] 7.2 Implement reset request with generic `202`, site scoping, email normalization, and account lookup; verify known, unknown, disabled-registration, and cross-site cases.
- [ ] 7.3 Implement durable reset mail jobs and a leased retry worker; verify restart, retry, terminal state, and no token logging.
- [ ] 7.4 Implement `POST /api/v1/auth/password/reset/confirm` with single-use consumption, password validation, and session revocation.
- [ ] 7.5 Implement reset rate limits by client IP and normalized email; verify `429`, `Retry-After`, and no token creation when limited.
- [ ] 7.6 Implement `POST /api/v1/auth/password/change` with current-password verification, session revocation, and CSRF checks.
- [ ] 7.7 Add tests for concurrent confirmation, resend invalidation, expired token, cross-site token, and invalid-password token retention.
- [ ] 7.8 Document reset and change endpoints, configuration, and delivery behavior in `docs/participation-api.md` and `docs/configuration.md`.

## 8. Reports, moderation log, and bans

- [ ] 8.1 Implement the report repository with creation, open-report deduplication, listing, and resolution; verify state transitions.
- [ ] 8.2 Implement `POST /api/v1/reports` with target read checks, self-report rejection, reason bounds, and idempotent repeats.
- [ ] 8.3 Implement `GET /api/v1/reports` and `POST /api/v1/reports/{id}/resolve` with community/site/deployment authority and conflict handling.
- [ ] 8.4 Implement the append-only moderation log repository and `GET /api/v1/modlog` with community and site scoping.
- [ ] 8.5 Implement community and site ban repositories with reason, expiry, revocation, and active-ban lookup.
- [ ] 8.6 Implement community ban routes and reject banned posting, replying, voting, and mentions with `403`.
- [ ] 8.7 Implement site ban routes and enforce active site bans during session resolution and every mutation without overwriting independent disabled state.
- [ ] 8.8 Make site bans revoke current sessions and make unban or expiry allow a new login; verify existing sessions fail immediately.
- [ ] 8.9 Write moderation log entries for report resolution, bans, post hiding, and community removals; verify append-only behavior.
- [ ] 8.10 Add report, modlog, ban, and revocation HTTP acceptance with unauthorized and conflicting requests.
- [ ] 8.11 Document moderation authority, report states, ban expiry, and log visibility in `docs/permissions.md` and `docs/api.md`.

## 9. Notifications for new events

- [ ] 9.1 Extend notification eligibility for target kinds and backfill existing post notifications; verify existing reply, like, and mention behavior.
- [ ] 9.2 Add moderation notification projection for report resolution and bans; verify recipient eligibility and idempotent replay.
- [ ] 9.3 Add target kind and identifier to notification representations; verify column, detail, and unread count responses.
- [ ] 9.4 Apply personal blocks and current target access to notification lists and unread counts; verify pre-existing notifications disappear while blocked.
- [ ] 9.5 Add notification retirement on inaccessible reports, bans, and targets; verify unblocking does not recreate retired events.
- [ ] 9.6 Add HTTP acceptance for report resolution and ban notifications, including duplicate worker delivery and inaccessible targets.

## 10. Federation integration

- [ ] 10.1 Extend activity parsing and dispatch for `Dislike` and `Undo` of `Dislike`; verify activity kind and payload validation.
- [ ] 10.2 Extend outbound activity construction for vote changes; verify `Like`, `Dislike`, and `Undo` selection and signing.
- [ ] 10.3 Reuse the Group Follow/Accept/Reject/Undo path for browser follows; verify local-only exclusion, policy-based rejection/pending, and remote state updates.
- [ ] 10.4 Add federation fixtures for remote downvote, duplicate delivery, blocked voter, and follow replay; verify no duplicate state.
- [ ] 10.5 Update `docs/federation.md` with vote and follow interoperability, and record live pinned-peer results separately from fixtures.

## 11. Documentation and integration

- [ ] 11.1 Update `docs/api.md` with all new endpoints, request bodies, success statuses, and error mappings.
- [ ] 11.2 Update `docs/forum-browser-api.md` with new DTO fields, unified threaded reads, account state, and route compatibility rules.
- [ ] 11.3 Update `docs/participation-api.md` with password reset and change behavior, including rate limits and session revocation.
- [ ] 11.4 Update `docs/permissions.md` with personal blocks, community bans, site bans, and report authority boundaries.
- [ ] 11.5 Update `docs/configuration.md` and `docs/runbook.md` with reset settings, worker enablement, migration order, and rollback notes.
- [ ] 11.6 Add an API contract note for the Elm frontend covering the additive DTO fields and new endpoints.
- [ ] 11.7 Run `make generate` and verify only expected `zz_*.gen.go` files change and no generated file is hand-edited.
- [ ] 11.8 Run `make build` and verify the server binary starts with the example configuration.
- [ ] 11.9 Run `make test` and verify all MyGO unit and HTTP tests pass.
- [ ] 11.10 Run `make test-postgres` and verify migrations, new repositories, and end-to-end HTTP acceptance pass on PostgreSQL.
- [ ] 11.11 Run `openspec validate complete-forum-core --strict` and verify the change remains valid.
- [ ] 11.12 Run a regression matrix over existing like, reply-root, site-admin hide, registration, notification, and federation tests; verify no behavior change.
- [ ] 11.13 Record any unavailable live peer or SMTP environment separately and do not claim acceptance that was not executed.
- [ ] 11.14 Document per-site vote settings and per-community follow policy in the API, runbook, and frontend contract docs; verify the examples match the implemented routes.

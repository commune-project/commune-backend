## Context

See `proposal.md` for motivation and the delta specs for behavior. The current backend stores topics and replies in one `posts` table, keeps one reaction row per Actor and post, records protocol follows in `follows`, enforces site-administrator actor/domain blocks through `site_actor_blocks` and `site_domain_blocks`, and writes internal security events to `audit_events`. Browser reads are centralized in `internal/storage/browser*`, while mutations are dispatched by `internal/server/forum*.mygo` and `internal/server/participation.mygo`. Migrations are explicit, numbered, and applied before the executable. MyGO sources are handwritten; generated `zz_*.gen.go` files are never edited.

## Goals / Non-Goals

**Goals:**

- Add the seven capabilities in the proposal without changing the meaning of existing like, flat-reply, or site-admin hide paths.
- Keep every new read and mutation behind the existing site resolution, session, origin, CSRF, pagination, and no-store conventions.
- Make personal blocks, community bans, and site bans effective across feeds, detail reads, search, notifications, and interaction checks.
- Keep the schema additive and deployable before the new executable.
- Cover the behavior with MyGO unit tests, PostgreSQL HTTP acceptance, and federation fixtures where the protocol changes.

**Non-Goals:**

- Private messages, public image proxying or thumbnails, OAuth, TOTP, email change, account deletion, or data export.
- Community icons, banners, tags, multi-community collections, custom emoji, or site taglines.
- Federated `Flag`, `Block`, or remote moderation propagation. Reports, bans, and modlog remain site-local in this change.
- Lemmy `v3`/`v4` API compatibility or full client interoperability.
- Frontend implementation. The Elm client consumes the documented API in a separate change.
- Denormalized score caches or a background ranking service.
- Site-level off switches for personal blocking, reports, password reset, saved content, read state, or personal hidden state. Those capabilities remain enabled for every site.

## Decisions

### Votes extend the existing reaction row

`reactions` already has one row per `(post_id, actor_uri)`, an activity URI, and an `undone_at` marker. The migration adds `score smallint NOT NULL DEFAULT 1 CHECK (score IN (-1,1))`; an active row is a vote, `undone_at` means zero, and existing rows backfill to `1`. `like_count` is the count of active `score = 1` rows, while `score`, `upvotes`, and `downvotes` are aggregate projections. `activities.kind` gains `Dislike`.

This avoids a second vote table that would duplicate the one-vote-per-actor invariant and complicate Like/Undo federation. The alternative, a new `post_votes` table, was rejected because it would require dual writes and a migration of existing reactions. The cost is that vote rows and like rows are the same storage, so all readers must consistently treat `undone_at` as zero and must not assume every row is an upvote.

### Per-site vote settings use a typed table

`site_vote_settings` has one row per site with `upvotes_enabled`, `downvotes_enabled`, `updated_at`, and `updated_by_actor_uri`. Both booleans default to true. A missing row resolves to true so existing sites and test fixtures remain valid. `GET /api/v1/site/vote-settings` exposes the resolved values; `PUT /api/v1/admin/vote-settings` performs a partial update for a site administrator or a deployment superadministrator and writes an audit event.

A disabled direction is excluded from vote mutation, aggregate counts, ordering, and inbound federation projection. Historical reaction rows are retained; re-enabling the direction makes them count again. This is intentionally a site-level policy, not a community override, because the requested behavior is one site controlling its own vote UI and acceptance. The alternative, a generic JSON settings table, was rejected because only two typed booleans are needed and a typed table gives database constraints and simple queries.

### Thread reads use one bounded recursive model

The reply tree is derived from the existing `posts.parent_id` with a recursive CTE. The root page is selected and paginated first, then descendants are fetched up to `max_depth`. The query orders siblings by the requested mode and uses `authored_at, id` as a stable tie-breaker. Existing `posts_parent` is retained and a `(parent_id, authored_at, id)` index is added. The root `items` are the direct replies existing clients already read, and each item carries nested `children`. `view=flat` is a deprecated presentation alias for `max_depth=1`, not a second query or a second response shape.

This avoids an `ltree` extension and a materialized path column. The alternative, adding `path` or `depth` to `posts`, would improve deep-tree reads but adds write-time maintenance for every reply and a backfill risk. If deep threads become a performance problem, a materialized path can be added later without changing the API.

### Password reset has its own token and mail tables

`password_reset_tokens` stores only a SHA-256 token digest, site, account, expiry, and consumption time. `password_reset_mail_jobs` mirrors the durable registration mail pattern: encrypted payload, attempts, availability, lease, and terminal state. A separate `password_reset_rate_limits` table mirrors the registration rate-limit shape. Token payloads use the existing AES-GCM helper pattern with a reset-specific associated-data label, and the outbox key remains outside the database.

Reusing `pending_registrations` was rejected because reset applies to existing accounts and has different uniqueness and lifecycle rules. Reusing `verification_mail_jobs` was rejected because its foreign key points at pending registrations. The cost is a small amount of duplicated worker code; the benefit is that registration and reset failures cannot corrupt each other's state.

### Community follows use a per-community policy

`communities.follow_policy` is `open`, `members`, `approval`, or `disabled`. `open` accepts an eligible follower immediately; `members` accepts only an approved member or manager and rejects other accounts; `approval` accepts members and managers and creates a pending row for other eligible accounts; `disabled` rejects new follows. Existing members-only communities are backfilled to `members` so their current protocol behavior is preserved. New communities derive the default from read policy unless the creator supplies a policy. Managers change the policy through the existing community policy endpoint, with validation and audit.

A local browser follow writes the existing `follows` row with a canonical local activity URI, the policy-derived state, and the local account's Actor URI. Manager approval runs the existing `SetMember` operation and the follow transition in one transaction. Federated communities queue the existing `Follow`/`Undo` and consume `Accept`/`Reject`; local-only communities skip federation. A remote replica uses the hosting site's authoritative state and never applies a local policy override. Policy changes do not delete existing follows or memberships; they govern new follow attempts.

A separate `browser_follows` table was rejected because it would create two truths for the same subscription and would not participate in the existing Group follower collection. Follow state remains distinct from membership except for the explicit restricted-community approval step, which intentionally grants both.

### Personal blocks are account-scoped view filters

`account_blocks` stores `(site_id, account_id, kind, target)` with kind `person`, `community`, or `instance`. Instance targets are normalized host names; person targets are Actor URIs; community targets are community IDs. A shared SQL predicate, expressed as a bound-parameter CTE or reusable `WHERE NOT EXISTS` fragment, is applied to community discovery, latest topics, community topics, reply trees, post detail, search, notifications, saved/read/liked lists, and aggregate counts.

The existing site-level block tables remain administrator policy and are not reused. Reusing them would make one user's block affect every account and would blur a security boundary. The cost is that every new read path must opt into the personal-block predicate; the task list and acceptance matrix therefore include a query-by-query review.

### Moderation gets purpose-built tables

`reports` stores reporter, target kind and ID, community scope when applicable, reason, state, resolver, resolution note, and timestamps. A partial unique index prevents duplicate open reports by the same reporter for the same target. `moderation_log` is append-only and records action, actor, scope, target, reason, and time. `community_bans` and `site_bans` store `actor_uri`, reason, expiry, revocation, and the acting account.

`audit_events` remains the security audit trail. It lacks reason, target kind, resolver, and expiry, and stretching it into a public modlog would mix two retention and disclosure contracts. Every new moderation mutation writes both its purpose-built row and, where appropriate, an audit event.

### Site bans are enforced without rewriting account disabled state

A site ban is an active row in `site_bans`. Session resolution rejects an account with an active ban, and all mutations recheck the ban. Creating a ban revokes the account's current sessions. Removing or expiring the ban allows a new login without guessing whether the account was independently disabled. This avoids setting `accounts.disabled` and later accidentally re-enabling an account that was disabled for another reason.

### Saved, read, and hidden state are separate per-account tables

`saved_posts`, `post_reads`, and `post_hidden` each key on `(site_id, account_id, post_id)`. They are independent of `site_posts.hidden_at`, which remains the site-administrator hide. The personal hidden endpoint is `POST/DELETE /api/v1/posts/{id}/hide-for-me` so the existing `/hide` contract is not broken. Feeds omit personally hidden posts; a direct detail read may return the post with `hidden_by_me: true`.

### Notifications gain a generic target

`notification_events` gains `target_kind` and `target_id`; `post_id` becomes nullable for non-post events. Existing rows backfill `target_kind = 'post'` and `target_id = post_id`. The projection and read queries branch by target kind: post events keep the existing visibility and block checks, while report and moderation events require the current recipient to remain the reporter or affected account and the target to remain eligible.

The alternative, a separate moderation-notification table, would duplicate cursor, read-all, unread-count, and retirement logic. The unified design costs one careful migration and a broader eligibility function, but keeps the browser notification contract single-shaped.

### API routing stays additive

New paths are added under the existing `/api/v1` surface: vote, site vote settings, follow, follow-requests, account blocks, reports, modlog, account saved/read/hidden/liked, save, read, and hide-for-me. The community route dispatch is widened from five to six segments for the follow decision path. `ParticipationRoute` gains account and moderation dispatch before the browser read dispatcher. Existing like, reply-root, and site-admin hide paths keep their current methods and meanings.

### Federation changes are limited to votes and follows

`internal/federation` gains `Dislike` parsing, signing, and delivery alongside `Like`; `Undo` resolves the original activity kind. Local votes on local-only posts produce no activity. Browser follows reuse the existing Group Follow/Accept/Reject/Undo path. Reports, bans, and modlog are intentionally local and do not emit `Flag` or `Block`.

## Risks / Trade-offs

- [Deep recursive reads can be expensive] → Bound `max_depth`, paginate roots, add the parent/time index, and keep the root page small.
- [A personal-block predicate can be missed in one query] → Centralize the predicate, add a query-by-query acceptance table, and test each listing with a blocked author, community, and instance.
- [Unified notification migration can break existing reply/like/mention rows] → Backfill before enabling the new projection, keep old rows on the post branch, and test replay, retirement, cursor, and unread counts.
- [Follow state and membership can diverge] → Approve or reject follow and membership in one transaction; test unfollow-keeps-membership and rejection-grants-nothing.
- [Site bans must not corrupt independently disabled accounts] → Enforce bans through `site_bans` and session checks; never use `accounts.disabled` as the ban flag.
- [Vote and Dislike interoperability can differ across peers] → Keep local-only exclusion, idempotent activity receipts, and pinned-peer fixtures; unknown activities remain tolerated.
- [Existing clients may ignore new DTO fields] → All additions are additive; root replies and the existing default sort remain available, and `view=flat` maps to one depth rather than a second implementation.
- [A site disables a vote direction while historical votes exist] → Retain the rows, exclude them from counts while disabled, and restore them on re-enable; test the transition in both directions.
- [A community follow policy change could strand pending requests] → Preserve existing rows, let managers resolve pending rows, and apply the new policy only to new attempts.
- [Reset mail can leak through logs or retries] → Store digests only, encrypt queued payloads with an out-of-database key, and test retry plus token invalidation.

## Migration Plan

1. Add forward migrations in order: votes and Dislike activity kind; password reset tokens, mail jobs, and rate limits; follow policy and indexes; account blocks; reports, moderation log, community bans, and site bans; saved/read/hidden tables; nullable notification targets; site vote settings.
2. Backfill existing reactions to active upvotes, existing members-only communities to `follow_policy = 'members'`, and existing notification events to post targets before the new executable serves traffic.
3. Deploy the additive schema first, then the new executable. Do not rewrite existing like, reply, or site-admin hide rows.
4. Enable password reset workers and SMTP only after the schema and configuration validate; registration can remain disabled independently.
5. Roll back by disabling the new routes and workers, then restoring the previous executable while retaining the additive schema and data. A down migration is not required for rollback; preserving new tables avoids data loss.

## Open Questions

- The exact `hot` and `controversial` weights can be tuned after initial use without changing the API or schema.
- Per-community vote overrides remain a later extension; this change deliberately keeps vote availability at the site level.
- Federated reports and moderation propagation remain a later compatibility decision.
- The frontend rollout order for the new DTO fields and endpoints is tracked separately.

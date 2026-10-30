## Why

Commune already supports multi-site communities, publishing, replies, likes, notifications, search, profiles, media, and FEP-1b12/FEP-7888 federation. It still lacks the interactions and safety controls people expect from a daily-use forum: users cannot recover a password, follow a community from the browser, block an actor, report content, or keep saved/read state. Moderation is limited to site-level hiding and internal audit rows, and replies can only be read one direct level at a time.

This change closes those gaps first, so Commune can be used as a forum before broader Lemmy feature parity work.

## What Changes

- Add post and reply voting with `score`, `upvotes`, and `downvotes`, a vote mutation endpoint, score-aware ordering, and compatibility with the existing like endpoints and ActivityPub `Like`/`Dislike` activities. Each site SHALL have its own audited upvote/downvote availability settings, so one site can disable downvotes without changing another site.
- Replace the separate flat and tree reply reads with one threaded reply query and one response model. The root `items` remain the direct replies existing clients already read, while `children`, `depth`, and `child_count` expose deeper discussion; `view=flat` is only a deprecated alias for `max_depth=1`.
- Add email-delivered, single-use, expiring password reset tokens with rate limits and generic acceptance responses, plus an authenticated password change endpoint.
- Add browser community follow/unfollow with a per-community `follow_policy` of `open`, `members`, `approval`, or `disabled`, viewer follow state, follower counts, and manager review of pending followers. Community managers control the policy; federated communities use the existing Follow/Accept/Reject/Undo activities.
- Add per-account blocking of persons, communities, and instances. Blocks filter feeds, detail reads, search, notifications, and interaction eligibility without changing site-administrator block policy.
- Add content reports, report listing and resolution, a moderation log, community bans, site bans, and moderation notifications. Reports cover posts, replies, communities, and persons.
- Add saved, read, hidden, and liked content lists with per-account mutation endpoints. The existing site-administrator post hide remains its own operation.
- Keep blocking, reports, password reset, saved, read, and personal-hidden features enabled for every site. This change adds no site-level off switches for them.
- Add additive migrations, backfill, API documentation, MyGO tests, and PostgreSQL acceptance coverage for the new behavior.

## Capabilities

### New Capabilities

- `forum-voting`: post and reply vote values, score aggregation, vote ordering, federation of Like/Dislike, and per-site upvote/downvote availability.
- `comment-threads`: one threaded reply model, depth and child-count metadata, thread ordering, and the deprecated `view=flat` depth alias.
- `password-reset`: email reset request and confirmation, token lifecycle, rate limits, and authenticated password change.
- `community-follows`: per-community follow policy, browser follow/unfollow, follower state, and pending-follow review.
- `user-blocking`: per-account person, community, and instance blocks and their read/interaction effects.
- `moderation-reports`: reports, report resolution, moderation log, community bans, and site bans.
- `saved-read-state`: saved, read, hidden, and liked lists for local accounts.

### Modified Capabilities

- `forum-browser-api`: post and community DTOs gain vote, follow, block, saved, read, and moderation fields; new read paths follow the existing pagination, visibility, and permission rules.
- `user-notifications`: moderation and report events become notification kinds, and personal blocks suppress ineligible notifications.
- `shared-forum-objects`: vote state becomes shared-object metadata, and inbound/outbound Dislike is accepted alongside Like.
- `group-federation`: browser follows honor each community's `follow_policy` across the existing Group Follow/Accept/Reject/Undo flow and approval review.

## Impact

- New forward migrations for votes, per-site vote settings, community follow policy, blocks, reports, moderation log entries, bans, and saved/read/hidden state; existing tables gain only additive columns.
- `internal/auth` gains reset-token helpers; `internal/storage` gains new repositories and visibility predicates; `internal/server` gains route dispatch and DTOs; `internal/federation` gains Dislike parsing and sending.
- `internal/server/browser_*`, `internal/storage/browser*`, feed, search, and notification queries need a shared personal-block filter so blocked content cannot leak through a secondary listing.
- `docs/api.md`, `docs/forum-browser-api.md`, `docs/participation-api.md`, `docs/federation.md`, and `docs/permissions.md` need the new contracts and moderation boundaries.
- The Elm frontend consumes the added DTO fields and endpoints; frontend implementation remains a separate change.
- No existing API path changes meaning. New paths are additive, and existing like, root reply, and site-admin hide behavior remains compatible.

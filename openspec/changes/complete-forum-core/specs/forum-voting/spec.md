## Purpose

Let local accounts express positive or negative votes on topics and replies, expose aggregate vote state, and order discussions by that state without breaking existing like behavior.

## ADDED Requirements

### Requirement: One current vote per account and target
The system SHALL allow a verified local account to hold at most one current vote on a readable post or reply. The vote value SHALL be `-1`, `0`, or `1`, where `0` means no active vote. Every post representation SHALL expose integer `score`, `upvotes`, and `downvotes`, integer `voted_by_me` in `{-1,0,1}`, and the compatibility field `like_count` equal to active upvotes. Undone votes SHALL NOT contribute to any count. Self-votes SHALL be allowed. Anonymous `voted_by_me` SHALL be `0`. Counts SHALL describe reactions known at the resolved site and SHALL NOT claim a complete federation-wide total.

#### Scenario: Change and clear a vote
- **WHEN** an account votes `1`, then `-1`, then `0` on the same readable post
- **THEN** the post ends with no active vote, and each response reflects the corresponding score, upvote, and downvote counts

#### Scenario: Independent voters
- **WHEN** two accounts cast different votes on one post
- **THEN** both votes remain independent and the aggregate score equals their sum

#### Scenario: Anonymous representation
- **WHEN** an anonymous reader requests a post with active votes
- **THEN** aggregate counts are returned and `voted_by_me` is `0`

### Requirement: Vote mutation and like compatibility
`POST /api/v1/posts/{id}/vote` SHALL accept a JSON body containing `score` and SHALL require current-site authentication, same-origin validation, and CSRF. It SHALL return `204` on success, `400` for a missing or invalid score, `401` without a session, `403` for origin or CSRF failure, and `404` for an unreceived, hidden, deleted, removed, rejected, or unreadable target. Repeating the current score SHALL be idempotent. Existing `POST /api/v1/posts/{id}/likes` SHALL remain an upvote operation and `DELETE` SHALL clear the caller's vote; clients using the like path SHALL observe the same state as the vote path.

#### Scenario: Like and vote share state
- **WHEN** a client likes a post through the existing like endpoint and then reads it through the vote endpoint
- **THEN** the post reports `voted_by_me: 1` and one active upvote

#### Scenario: Invalid or unauthorized vote
- **WHEN** a request omits `score`, uses a value outside `{-1,0,1}`, omits CSRF, or targets an unreadable post
- **THEN** the server returns the documented `400`, `403`, or `404` response and changes no vote

#### Scenario: Tombstone vote
- **WHEN** an authenticated account votes on a tombstoned or removed post
- **THEN** the vote is rejected without creating a reaction row

### Requirement: Per-site vote settings
`GET /api/v1/site/vote-settings` SHALL return the resolved site's `upvotes_enabled` and `downvotes_enabled` booleans, both defaulting to `true` when no setting row exists. `PUT /api/v1/admin/vote-settings` SHALL accept a JSON object containing at least one of those booleans and SHALL require site-administrator authority, same-origin validation, and CSRF. It SHALL return the full settings object, `400` for an empty, non-boolean, or unknown field, `401` without a session, and `403` for insufficient authority. Changes SHALL be site-scoped, audited, and effective on the next request. A deployment superadministrator MAY update the site resolved by the request authority even when they do not administer it; a site administrator SHALL update only their own site. Site A's settings SHALL NOT affect site B.

#### Scenario: Disable downvotes at one site
- **WHEN** a site administrator sets `downvotes_enabled: false` for site A
- **THEN** site A hides and rejects new downvotes while site B remains unchanged

#### Scenario: Partial update
- **WHEN** an administrator submits only `{"downvotes_enabled": false}`
- **THEN** the stored `upvotes_enabled` value is preserved and the full response is returned

#### Scenario: Invalid update
- **WHEN** an administrator submits an empty body, a string value, or an unknown setting
- **THEN** the server returns `400` and changes no setting

### Requirement: Disabled vote direction
When a site disables `upvotes` or `downvotes`, new votes of that direction SHALL return `403 feature_disabled`; clearing an existing vote SHALL remain allowed. The disabled direction SHALL be excluded from `upvotes`, `downvotes`, `score`, and `voted_by_me`, even when historical reaction rows remain stored. An inbound `Like` or `Dislike` for a disabled direction SHALL be accepted idempotently but SHALL NOT create or update a vote. Re-enabling the direction SHALL restore counting of the retained historical rows. Post permissions SHALL expose `can_upvote` and `can_downvote` consistently with the current site settings, and `can_vote` SHALL be true only when at least one direction is enabled.

#### Scenario: Historical downvotes return after re-enable
- **WHEN** a site disables downvotes, then re-enables them
- **THEN** downvotes are hidden from counts while disabled and retained rows count again after re-enable

#### Scenario: Federated disabled vote
- **WHEN** a signed remote `Dislike` arrives at a site with downvotes disabled
- **THEN** the receipt is accepted without changing post vote state

#### Scenario: Clear remains allowed
- **WHEN** an account with an existing downvote clears it while downvotes are disabled
- **THEN** the clear succeeds and the vote becomes zero

### Requirement: Score-aware discussion ordering
`GET /api/v1/topics`, `GET /api/v1/communities/{id}/topics`, and reply listings SHALL accept `sort` values `new`, `old`, `top`, `hot`, and `controversial`. Topic listings SHALL default to `new` and preserve authored-time descending ordering; reply listings SHALL default to `old` and preserve authored-time ascending ordering. `top` SHALL order by aggregate score, `hot` SHALL combine score with recency, and `controversial` SHALL favour items with substantial opposing votes. All modes SHALL apply visibility, reception, deletion, hiding, inclusion, and personal-block filters before pagination, and SHALL use authored time and ID as deterministic tie-breakers. An unsupported sort value SHALL return `400`.

#### Scenario: Top ordering after vote change
- **WHEN** a lower-scored post receives enough upvotes to exceed a previously higher-scored post
- **THEN** the next `sort=top` page places it first

#### Scenario: Filters before pagination
- **WHEN** high-scoring posts are unreadable, deleted, hidden, removed, rejected, or blocked by the viewer
- **THEN** they do not consume the requested page's limit or offset

#### Scenario: Invalid sort
- **WHEN** a client requests `sort=random`
- **THEN** the server returns `400` without returning a page

### Requirement: Federated vote representation
An inbound ActivityPub `Like` SHALL record an upvote, `Dislike` SHALL record a downvote, and `Undo` of either SHALL clear the actor's active vote. Inbound votes SHALL be idempotent by activity identity and SHALL require the existing signature and authority checks. A local vote change on a federated post SHALL enqueue the corresponding `Like`, `Dislike`, or `Undo` activity for eligible recipients. Local-only posts SHALL NOT produce vote activities. A remote vote SHALL NOT be accepted from an actor blocked at the resolved site.

#### Scenario: Remote downvote
- **WHEN** a signed remote `Dislike` arrives for a readable federated post
- **THEN** the post's score decreases by one and a repeated delivery does not decrease it again

#### Scenario: Local vote activity
- **WHEN** a local account changes an upvote to a downvote on a federated post
- **THEN** one eligible `Dislike` activity replaces the prior vote state without leaving an active `Like`

#### Scenario: Local-only exclusion
- **WHEN** an account votes on a local-only post
- **THEN** the vote is stored locally and no federated activity or delivery job is created

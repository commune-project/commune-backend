## Purpose

Let each community decide whether accounts may follow it, whether membership is required, and whether non-members need manager approval, while keeping follow state separate from membership unless approval explicitly grants it.

## ADDED Requirements

### Requirement: Community follow policy
Each community SHALL have a `follow_policy` of `open`, `members`, `approval`, or `disabled`. `open` SHALL allow an eligible account to follow immediately. `members` SHALL allow only a current approved member or manager to follow. `approval` SHALL allow members and managers immediately and SHALL create a pending request for another eligible account. `disabled` SHALL reject new follows. The policy SHALL be authoritative at the community's hosting site; a remote replica SHALL use the authoritative federated state and SHALL NOT override it locally. New communities SHALL accept an optional `follow_policy`; when omitted, `eligible_users` read policy SHALL derive `open` and `members` read policy SHALL derive `members`. Existing members-only communities SHALL be backfilled to `members` so their current federation behavior is preserved.

#### Scenario: Open policy
- **WHEN** an eligible account follows a hosted community whose policy is `open`
- **THEN** the follow becomes accepted immediately and is distinct from membership

#### Scenario: Membership policy
- **WHEN** a non-member follows a hosted community whose policy is `members`
- **THEN** the server returns `403` and creates no pending request

#### Scenario: Approval policy
- **WHEN** a non-member follows a hosted community whose policy is `approval`
- **THEN** the follow becomes pending and no membership is granted before manager approval

#### Scenario: Disabled policy
- **WHEN** an eligible account attempts to follow a hosted community whose policy is `disabled`
- **THEN** the server returns `403` and creates no follow row

### Requirement: Browser follow and unfollow
`POST /api/v1/communities/{id}/follow` and `DELETE /api/v1/communities/{id}/follow` SHALL require current-site authentication, same-origin validation, and CSRF, and SHALL return `204` on success. Follow SHALL be idempotent and SHALL apply the hosted community's `follow_policy`; unfollow SHALL mark the caller's current follow undone and SHALL remain available when new follows are disabled. An unknown, unreceived, or unreadable community SHALL return `404`; an ineligible account SHALL return `403`; `members` without membership and `disabled` SHALL return `403` with a stable feature or membership error. Local-only communities SHALL NOT create federation activities. A federated community follow or unfollow SHALL use the existing Actor-signed `Follow`, `Undo`, `Accept`, and `Reject` flow.

#### Scenario: Follow an open community
- **WHEN** an eligible account follows a readable open federated community
- **THEN** the follow becomes accepted, the follower count increases once, and membership remains separate

#### Scenario: Unfollow after policy change
- **WHEN** a community changes to `disabled` and an existing follower unfollows
- **THEN** the follow becomes undone without granting or revoking membership

#### Scenario: Invalid target
- **WHEN** a caller follows an unknown or unreadable community
- **THEN** the server returns `404` and stores no follow row

### Requirement: Policy management
`PUT /api/v1/communities/{id}/policy` SHALL accept the existing `read_policy` and `post_policy` fields and an optional `follow_policy`. The caller SHALL require current community management authority, same-origin validation, and CSRF. An invalid `follow_policy` SHALL return `400`. Changing the policy SHALL NOT delete existing follows, memberships, or delivery jobs; it SHALL affect new follow attempts from the next request. Every accepted policy change SHALL write an audit event. Community representations SHALL expose `follow_policy` and the viewer's current `is_following`, `follow_state`, and `can_follow`; `can_follow` SHALL be false for `disabled`, for `members` without membership, and for an already accepted or pending follow.

#### Scenario: Manager disables follows
- **WHEN** a manager changes a community from `open` to `disabled`
- **THEN** new follows are rejected, existing followers and counts remain, and the change is audited

#### Scenario: Non-manager changes policy
- **WHEN** an ordinary member submits a policy change
- **THEN** the server returns `403` and the policy is unchanged

#### Scenario: Policy projection
- **WHEN** an account reads a community whose policy is `approval`
- **THEN** `follow_policy` is `approval`, a non-member viewer has `can_follow: true` when no request exists, and an already pending viewer has `follow_state: pending`

### Requirement: Viewer follow state and counts
Community representations SHALL expose `viewer.is_following`, `viewer.follow_state` in `none|pending|accepted|rejected|undone`, integer `follower_count`, and the current `follow_policy`. Anonymous viewers SHALL receive `false`, `none`, zero, and the public policy. The count SHALL include accepted follows only and SHALL exclude undone, pending, and rejected rows. A restricted community SHALL NOT disclose follower identities or counts to a caller without current management authority. Follow state SHALL reflect the current account and site, not a cached session value.

#### Scenario: Accepted follow in community detail
- **WHEN** an account with an accepted follow reads the community
- **THEN** `is_following` is true, `follow_state` is `accepted`, and the count includes that follow once

#### Scenario: Anonymous restricted community
- **WHEN** an anonymous reader requests a members-only community it may not read
- **THEN** the server returns `404` rather than a count or follower list

#### Scenario: Revoked follow
- **WHEN** a manager rejects a pending follow or the account unfollows
- **THEN** the next community response reflects the rejected or undone state and the count excludes it

### Requirement: Manager review of pending follows
`GET /api/v1/communities/{id}/follow-requests` SHALL require current community management authority and SHALL return a paginated roster of pending follows. New pending rows SHALL be created only while the current policy is `approval`; `members` and `disabled` SHALL not create new pending rows. Existing pending rows SHALL remain reviewable after a policy change. `POST /api/v1/communities/{id}/follow-requests/{actor}` SHALL accept `state` of `accepted` or `rejected` and SHALL require the same authority, origin, and CSRF checks. Approval SHALL atomically set the follow to accepted and approve the actor's community membership. Rejection SHALL set the follow to rejected and SHALL NOT grant membership. The mutation SHALL be idempotent, SHALL write an audit event, and SHALL queue a signed `Accept` or `Reject` for a federated follower. A local-only community SHALL NOT queue a federation activity.

#### Scenario: Approve a pending follower
- **WHEN** a manager approves a pending follow for an `approval` community
- **THEN** the follower becomes an approved member, the follow becomes accepted, and the follower can read the community

#### Scenario: Reject a pending follower
- **WHEN** a manager rejects a pending follow
- **THEN** the follow becomes rejected, no membership is created, and the follower remains unable to read restricted content

#### Scenario: Review after policy change
- **WHEN** a community changes from `approval` to `members` while a pending row exists
- **THEN** the manager can still accept or reject that existing row, while new follows use `members` and create no new pending row

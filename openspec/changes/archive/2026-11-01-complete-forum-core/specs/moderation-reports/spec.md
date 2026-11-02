## Purpose

Give readers a way to report harmful content and give community managers and site administrators a durable, auditable workflow for resolving reports, applying bans, and reviewing moderation history.

## ADDED Requirements

### Requirement: Report creation
`POST /api/v1/reports` SHALL accept `target_kind` of `post`, `community`, or `person`, a target identifier, and a reason of 1 to 1000 Unicode code points. It SHALL require current-site authentication, same-origin validation, and CSRF, and SHALL require the caller to be able to read the target. It SHALL return `201` on the first open report by that reporter for that target, `200` for an idempotent repeat, `400` for invalid input, `401` without a session, `403` for origin or CSRF failure, `404` for an unreadable or unknown target, and `429` when a configured report limit is exceeded. A reporter SHALL NOT be able to report their own identity. A report SHALL retain the target identity and a snapshot of the reason without exposing reporter identity to ordinary readers.

#### Scenario: Report a post
- **WHEN** a reader reports a readable post with a valid reason
- **THEN** one open report is stored and the reader receives `201`

#### Scenario: Duplicate open report
- **WHEN** the same reader reports the same target again while the first report is open
- **THEN** the response is `200` and no second open report is created

#### Scenario: Unreadable target
- **WHEN** a reader reports an unreceived, hidden, or unreadable post
- **THEN** the server returns `404` and stores no report

### Requirement: Report review and resolution
`GET /api/v1/reports` SHALL return a paginated report list filtered by optional `state` of `open`, `resolved`, or `rejected` and optional `community_id`. Community managers SHALL see reports for their community; site administrators SHALL see all reports at their site; deployment administrators SHALL see all reports in the deployment; other accounts SHALL receive `403`. `POST /api/v1/reports/{id}/resolve` SHALL accept `state` of `resolved` or `rejected` and an optional note, require current review authority, and atomically record the resolver, resolution time, and note. Repeating the same resolution SHALL be idempotent; a conflicting second resolution SHALL return `409`. Resolution SHALL create a moderation log entry and SHALL notify the reporter when the reporter is a local account and the target remains eligible. Report rows SHALL NOT disclose private content beyond the target fields already visible to the reviewer.

#### Scenario: Community manager resolves a report
- **WHEN** a manager resolves an open report for their community
- **THEN** the report becomes resolved with a resolver, note, and log entry, and the reporter receives one notification

#### Scenario: Unauthorized review
- **WHEN** an ordinary member requests the report list or resolves a report
- **THEN** the server returns `403` without report content

#### Scenario: Concurrent conflicting resolutions
- **WHEN** two reviewers resolve the same open report with different states
- **THEN** exactly one succeeds and the other receives `409`

### Requirement: Moderation log
`GET /api/v1/modlog` SHALL return a paginated, newest-first list of moderation actions with `id`, `action`, `actor_actor_uri`, optional `community_id`, `target_kind`, `target_id`, `reason`, and `created_at`. It SHALL accept an optional `community_id` filter and SHALL require community management authority for that community or site/deployment administration authority for the requested scope. Actions SHALL include post hide/unhide, community post removal/restore, community ban/unban, site ban/unban, and report resolution. Log rows SHALL be append-only and SHALL NOT be editable or deletable through the API. Existing internal audit events MAY remain separate, but every moderation endpoint in this capability SHALL produce a log row.

#### Scenario: Manager reads community log
- **WHEN** a community manager requests the log for their community
- **THEN** only actions scoped to that community are returned with reasons and timestamps

#### Scenario: Site administrator reads site log
- **WHEN** a site administrator requests the log without a community filter
- **THEN** site-scoped actions and actions for communities hosted at that site are returned

#### Scenario: Ordinary member reads log
- **WHEN** an ordinary member requests a community log
- **THEN** the server returns `403`

### Requirement: Community and site bans
`POST /api/v1/communities/{id}/bans` and `DELETE /api/v1/communities/{id}/bans` SHALL accept `actor`, `reason`, and optional `expires_at` and SHALL require current community management authority. `POST /api/v1/admin/bans` and `DELETE /api/v1/admin/bans` SHALL accept the same fields and SHALL require site-administrator authority. A community ban SHALL prevent the actor from posting, replying, voting, or mentioning in that community while active. A site ban SHALL prevent the actor from authenticating or interacting anywhere at that site and SHALL revoke the local account's current sessions, without overwriting an independent account-disabled state. Expired bans SHALL cease to apply without a manual unban. Creating an already active ban SHALL be idempotent; removing an absent ban SHALL return `404`. Every change SHALL write a moderation log entry and notify an affected local account when eligible.

#### Scenario: Community ban blocks posting
- **WHEN** a manager bans an actor from a community and the actor attempts to publish there
- **THEN** the request returns `403` and no post is created

#### Scenario: Site ban revokes local sessions
- **WHEN** a site administrator bans a local account
- **THEN** existing sessions are revoked and subsequent authentication or interaction at that site fails without changing an independent account-disabled flag

#### Scenario: Expired ban
- **WHEN** a ban's `expires_at` has passed
- **THEN** the actor can interact again without an explicit unban and the history remains in the log

## ADDED Requirements

### Requirement: Extended post interaction metadata
Every successful browser post representation, including topic and reply lists, post detail, search results, saved/read/liked lists, publication, editing, and import, SHALL retain existing fields and add integer `score`, `upvotes`, and `downvotes`, integer `voted_by_me` in `{-1,0,1}`, boolean `saved_by_me`, boolean `read_by_me`, and boolean `hidden_by_me`. `like_count` SHALL remain present and equal active upvotes. Anonymous viewers SHALL receive zero counts and false personal flags. Personal flags SHALL reflect only the current account and site. The `permissions` object SHALL add `can_vote`, `can_upvote`, `can_downvote`, `can_save`, and `can_hide_for_me`; existing permission fields SHALL remain. `can_upvote` and `can_downvote` SHALL reflect the resolved site's vote settings; `can_vote` SHALL be true only when at least one direction is enabled. These fields SHALL be derived from current access and SHALL NOT replace mutation checks.

#### Scenario: Authenticated post detail
- **WHEN** an authenticated reader requests a readable post after voting, saving, and marking it read
- **THEN** the response exposes the current score, `voted_by_me`, `saved_by_me: true`, `read_by_me: true`, and the existing interaction fields

#### Scenario: Anonymous post detail
- **WHEN** an anonymous reader requests a public post
- **THEN** vote counts are present, personal flags are false, and personal mutation permissions are false

### Requirement: Extended community viewer state
Community representations from discovery, detail, creation, and follow responses SHALL add `follow_policy`, `viewer.is_following`, `viewer.follow_state`, `viewer.can_follow`, and integer `follower_count`. `follow_policy` SHALL be one of `open`, `members`, `approval`, or `disabled`. `follow_state` SHALL be one of `none`, `pending`, `accepted`, `rejected`, or `undone`. Anonymous viewers SHALL receive the public policy, `false`, `none`, `false`, and zero. A restricted community SHALL NOT disclose follower counts or identities to a caller without current management authority. Follow fields SHALL reflect current account, site, policy, and membership state.

#### Scenario: Followed community
- **WHEN** an account with an accepted follow reads the community
- **THEN** `viewer.is_following` is true and `follower_count` includes that follow once

#### Scenario: Anonymous restricted community
- **WHEN** an anonymous reader requests a members-only community it may not read
- **THEN** the server returns `404` without follower metadata

### Requirement: New browser routes retain access and pagination rules
All new browser routes in this change SHALL use the existing site-resolution, authentication, origin, CSRF, no-store, JSON, pagination, and error conventions. Listing routes SHALL apply current access, reception, deletion, hiding, community inclusion, and personal-block filters before pagination. Invalid pagination, sort, depth, block kind, target, or report state SHALL return `400`. Missing or unreadable resources SHALL return `404`. Unsupported methods SHALL return `405` with an appropriate `Allow` header. Authorization and storage failures SHALL NOT be converted into empty success pages or false permissions.

#### Scenario: Unsupported method
- **WHEN** a client sends `PUT` to a new read-only listing route
- **THEN** the server returns `405` with `Allow` and does not mutate state

#### Scenario: Filtering before pagination
- **WHEN** blocked, hidden, deleted, and unreadable rows are newer than eligible rows
- **THEN** the page contains the requested number of eligible rows without counting excluded rows toward limit or offset

#### Scenario: Storage failure
- **WHEN** a listing cannot determine current access because storage is unavailable
- **THEN** the response is a failure status, not an empty page or anonymous success

## Purpose

Let each local account hide persons, communities, and instances from its own forum experience, and prevent blocked actors from interacting with it, without changing site-administrator policy for other users.

## ADDED Requirements

### Requirement: Personal block management
`GET /api/v1/account/blocks` SHALL list the current account's blocks with `kind`, `target`, and `created_at`. `POST /api/v1/account/blocks` and `DELETE /api/v1/account/blocks` SHALL accept `kind` of `person`, `community`, or `instance` and a canonical `target`, and SHALL require authentication, same-origin validation, and CSRF. Person targets SHALL be Actor URIs, community targets SHALL be community IDs, and instance targets SHALL be normalized lower-case host names without a path. The operation SHALL be idempotent and site-scoped. Self-blocking and blocking the resolved site's own instance SHALL return `400`. Unknown or malformed targets SHALL return `400`; a block SHALL NOT delete content or alter another account's view. Personal blocks SHALL remain distinct from existing site-administrator actor and domain blocks.

#### Scenario: Block and unblock a person
- **WHEN** an account blocks a remote person and later unblocks it
- **THEN** the block list contains one row in between, and the person's content becomes visible again only after unblocking

#### Scenario: Invalid self block
- **WHEN** an account attempts to block its own Actor or the site's own instance
- **THEN** the request returns `400` and no block is stored

#### Scenario: Other accounts unaffected
- **WHEN** one account blocks a community
- **THEN** another account at the same site continues to see that community's readable content

### Requirement: Block-aware reads and counts
Personal blocks SHALL filter community discovery, latest topics, community topics, reply trees, post detail, search results, notifications, and interaction counts. A post whose author is a blocked person, whose community is blocked, or whose author belongs to a blocked instance SHALL be absent. A reply tree SHALL also omit descendants of an excluded reply. Filters SHALL apply before pagination and count aggregation. A direct request for excluded content SHALL return `404` without body, author handle, or count metadata. Notifications from blocked actors or targets SHALL contribute neither rows nor unread counts.

#### Scenario: Blocked author in feed
- **WHEN** a blocked person authors a newer topic
- **THEN** the topic is absent and does not consume a page slot

#### Scenario: Blocked instance in search
- **WHEN** a search would otherwise return a post whose author's host is blocked
- **THEN** the result is absent and the page remains correctly bounded

#### Scenario: Direct blocked post
- **WHEN** a viewer requests a post authored by a blocked person by ID
- **THEN** the server returns `404` rather than a post marked hidden

### Requirement: Blocked interaction eligibility
A blocked actor SHALL NOT be able to reply to, vote on, mention, or otherwise interact with the blocking account's content. Attempts SHALL return `403` and SHALL create no post, vote, mention, or notification. The restriction SHALL apply in both directions for the pair's interactions while the block exists. A block SHALL NOT retroactively delete existing shared content; it only changes the blocking account's reads and the pair's future interactions.

#### Scenario: Blocked reply
- **WHEN** a blocked actor attempts to reply to the blocker's post
- **THEN** the request is rejected and no reply or notification is created

#### Scenario: Blocked mention
- **WHEN** a blocked actor mentions the blocker in a new post
- **THEN** the mention is not activated and the blocker receives no notification

#### Scenario: Existing content remains shared
- **WHEN** an account blocks an author after reading an existing post
- **THEN** the post remains available to other accounts and is merely excluded from the blocker's views

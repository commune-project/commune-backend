## Purpose

Let each local account retain its own saved, read, hidden, and liked content state across sessions without changing shared posts or another account's view.

## ADDED Requirements

### Requirement: Saved content
`POST /api/v1/posts/{id}/save` and `DELETE /api/v1/posts/{id}/save` SHALL require current-site authentication, same-origin validation, and CSRF, and SHALL return `204` on success. They SHALL be idempotent and SHALL act only on the caller's saved state. A caller MUST currently be able to read the post; an unreceived, deleted, hidden, removed, rejected, or unreadable post SHALL return `404` and create no row. `GET /api/v1/account/saved` SHALL return the caller's saved posts using the existing post page shape and ordering by save time descending then post ID. Current read access SHALL be rechecked on every listing; an inaccessible saved post SHALL be omitted without leaking its content. Saved state SHALL be per site and per account.

#### Scenario: Save and list
- **WHEN** an account saves a readable post and later requests its saved list
- **THEN** the post appears once with current metadata and saved state

#### Scenario: Access revoked after save
- **WHEN** a saved post becomes unreadable because membership is revoked or the community policy tightens
- **THEN** the saved list omits it and does not expose its title or body

#### Scenario: Save a tombstone
- **WHEN** an account saves a deleted or hidden post by ID
- **THEN** the server returns `404` and stores no saved row

### Requirement: Read and hidden state
`POST /api/v1/posts/{id}/read` SHALL mark a readable post read for the caller and SHALL be idempotent. `GET /api/v1/account/read` SHALL return the caller's read posts. `POST /api/v1/posts/{id}/hide-for-me` and `DELETE /api/v1/posts/{id}/hide-for-me` SHALL set or clear the caller's personal hidden state and SHALL NOT change the existing site-administrator hide operation or `site_posts.hidden_at`. Personal hidden posts SHALL be omitted from latest, community, search, and saved/read/liked feeds, while a direct post read MAY still return the post with `hidden_by_me: true`. Current access SHALL be rechecked on every listing. Hidden, read, and saved state SHALL NOT affect other accounts or the shared object.

#### Scenario: Hide for me
- **WHEN** an account hides a readable post for itself
- **THEN** the post disappears from its feeds but remains visible to other accounts and the site-admin hide state is unchanged

#### Scenario: Read is idempotent
- **WHEN** an account marks the same post read repeatedly
- **THEN** one read record is retained and the read list contains the post once

#### Scenario: Direct hidden post
- **WHEN** an account requests a post it personally hid by ID
- **THEN** the response may include the post with `hidden_by_me: true` and does not expose another account's hidden state

### Requirement: Liked and voted content
`GET /api/v1/account/liked` SHALL return posts on which the caller has an active upvote, ordered by vote time descending then post ID. The list SHALL use the existing post page shape and SHALL recheck current read access, deletion, hiding, inclusion, and personal blocks. A downvote SHALL NOT appear in the liked list. The endpoint SHALL NOT claim to list another account's votes.

#### Scenario: Like appears in list
- **WHEN** an account upvotes a readable post
- **THEN** the post appears in its liked list with current vote and interaction metadata

#### Scenario: Downvote is excluded
- **WHEN** an account changes an upvote to a downvote
- **THEN** the post disappears from the liked list while the downvote remains counted on the post

#### Scenario: Revoked access
- **WHEN** a liked post becomes unreadable
- **THEN** it is omitted from the liked list without leaking its content

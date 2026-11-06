## Purpose

Provide authenticated mention candidate discovery for composers using only already stored account and actor data, without performing federation network discovery.

## ADDED Requirements

### Requirement: Authenticated candidate lookup
`GET /api/v1/mentions/candidates` SHALL require a valid current-site browser session and SHALL return `401` when the request is unauthenticated or the session is invalid. It SHALL accept a required `q` parameter trimmed to between 2 and 64 Unicode scalar values, reject invalid UTF-8, NUL, empty, or out-of-range values with `400`, and accept an optional `limit` that defaults to 8, has a maximum of 20, and rejects non-integer, zero, negative, or excessive values with `400`. Unsupported methods SHALL return `405`. Every response SHALL include `Cache-Control: no-store` and `Referrer-Policy: no-referrer`.

#### Scenario: Anonymous request
- **WHEN** a client without a valid session requests mention candidates
- **THEN** the server returns `401` without returning account or actor data

#### Scenario: Invalid query or limit
- **WHEN** `q` is shorter than two characters, longer than 64 characters, invalid UTF-8, or contains NUL, or `limit` is zero, negative, non-integer, or greater than 20
- **THEN** the server returns `400` and no candidate items

#### Scenario: Unsupported method
- **WHEN** a client sends a non-GET request to the candidate endpoint
- **THEN** the server returns `405`

### Requirement: Optional community context
The endpoint SHALL accept an optional `community_id` parameter and SHALL NOT require it. Candidate selection SHALL NOT depend on the presence, validity, readability, membership, federation mode, or posting policy of that community, and supplying it SHALL NOT add a community access check. The endpoint SHALL NOT evaluate notification or delivery eligibility; those checks remain part of saving the post, where an ineligible mention is dropped without changing the candidate response.

#### Scenario: No community context
- **WHEN** a composer requests candidates without `community_id`
- **THEN** the response contains the same eligible local and stored remote candidates that a community-scoped request would return

#### Scenario: Present but ineligible community context
- **WHEN** a composer supplies a `community_id` for a community where a returned remote actor could not receive a notification
- **THEN** the actor may still appear as a candidate, and saving the post drops the ineligible mention

### Requirement: Candidate inclusion and public projection
The response SHALL contain only site-local Person accounts of the resolved site and other Person Actors already stored in the deployment that have a usable handle. Site-local accounts SHALL be non-disabled accounts of the resolved site. Remote candidates SHALL include stored remote Persons with a non-empty stored handle and Persons hosted by another configured site whose local account and canonical origin yield a handle. An Actor without a stored or derivable `username@domain` handle SHALL NOT be returned because the client cannot insert a valid mention for it. The response SHALL use `{items:[...]}` with each item containing string fields `actor_uri`, `acct`, `display_name`, and `avatar`; fields SHALL be empty strings rather than null when absent. `acct` SHALL be the full `username@domain` handle without a leading `@`; `display_name` SHALL fall back to the account username for an account-backed candidate without a profile; `avatar` SHALL be empty when no stored avatar exists. Each Actor SHALL appear at most once.

#### Scenario: Local account candidate
- **WHEN** a local account matches the query and has no profile display name or avatar
- **THEN** its item contains the account Actor URI, `username@canonical-origin`, the username as `display_name`, and an empty `avatar`

#### Scenario: Stored remote candidate
- **WHEN** a remote Person already stored with a verified handle matches the query
- **THEN** its item uses the stored handle as `acct` and its stored display name and avatar, or empty strings when absent

#### Scenario: Colocated site candidate
- **WHEN** a Person is local to another configured site in the same deployment and has a local account and canonical origin
- **THEN** it is returned as a remote candidate with a handle derived from that account and origin

#### Scenario: Actor without a usable handle
- **WHEN** a stored remote Person has no verified handle and is not a local account of another configured site
- **THEN** the endpoint omits it instead of inventing or resolving a handle

### Requirement: Candidate visibility filtering
Candidates SHALL exclude the requesting account, disabled accounts of the resolved site or another configured site, Actors blocked by the resolved site at the actor or domain level, Actors with an active site ban, and Actors the viewer has personally blocked as a person or instance. These filters SHALL apply before the result limit and SHALL NOT be deferred to post saving.

#### Scenario: Self and disabled accounts
- **WHEN** the query matches the requesting account or a disabled local account
- **THEN** neither appears in the response

#### Scenario: Site and personal blocks
- **WHEN** the query matches an Actor blocked by the resolved site or by the viewer's personal block list
- **THEN** that Actor does not appear in the response

#### Scenario: Active site ban
- **WHEN** the query matches an Actor with an active site ban
- **THEN** that Actor does not appear in the response

### Requirement: Bounded deterministic matching
Matching SHALL be literal, case-insensitive, and based on local username or display name and remote handle or display name. User-supplied percent, underscore, backslash, and quote characters SHALL be matched literally and SHALL NOT become SQL wildcards or executable syntax. Candidates whose handle or display name begins with the trimmed query SHALL sort before candidates that only contain it; remaining ties SHALL sort by case-insensitive handle and then Actor URI. The limit SHALL be applied after filtering and ordering.

#### Scenario: Prefix priority
- **WHEN** one matching handle starts with the query and another only contains it
- **THEN** the prefix match appears first

#### Scenario: Literal punctuation
- **WHEN** the query contains percent, underscore, backslash, or quote characters
- **THEN** only literal matches are returned and query structure is unchanged

#### Scenario: Stable bounded result
- **WHEN** multiple candidates share the same prefix rank and case-insensitive handle
- **THEN** Actor URI breaks the tie and at most `limit` items are returned

### Requirement: No federation side effects
The endpoint SHALL read only already stored data. It SHALL NOT perform WebFinger, Actor, media, or other outbound HTTP requests; SHALL NOT enqueue discovery or delivery work; and SHALL NOT write account, actor, job, or notification state. Unknown or incomplete remote handles SHALL remain absent from the response.

#### Scenario: Unknown remote handle
- **WHEN** a query resembles a remote handle that is not already stored with a usable `acct`
- **THEN** the endpoint returns no invented candidate and performs no WebFinger or Actor fetch

#### Scenario: Read-only lookup
- **WHEN** a candidate request succeeds
- **THEN** no actor-handle job, delivery job, notification, or other persistent state is created or updated

## ADDED Requirements

### Requirement: Handle-based public profile lookup
`GET /api/v1/profiles/{acct}` SHALL accept either a bare username or a
`username@domain` handle. A bare username SHALL resolve only to a non-disabled
account of the requesting site and SHALL preserve existing behavior. A handle SHALL
resolve first to a non-disabled local account whose site authority matches the
handle domain, including sites other than the requesting site, and otherwise to a
stored Person Actor whose verified handle matches case-insensitively. The response
SHALL include `actor_uri`, `acct`, `username`, `display_name`, `biography`,
`biography_html`, `avatar_url`, and `updated_at`. `acct` SHALL be the full
`username@domain` handle without a leading `@`; `username` SHALL be the local account
name and SHALL be empty for a remote Person. Unmatched, malformed, disabled, or
blocked profiles SHALL return `404` without revealing which condition applied. Site
actor blocks, site domain blocks, and active site bans SHALL apply to every read; a
valid session SHALL additionally apply the viewer's personal person and instance
blocks. The endpoint SHALL NOT perform WebFinger, Actor, or media discovery unless
`resolve=1` is supplied.

#### Scenario: Current-site username
- **WHEN** a client requests a bare username that belongs to a non-disabled account of the requesting site
- **THEN** the response contains that account's Actor URI, canonical handle, username, and stored profile fields

#### Scenario: Account of another configured site
- **WHEN** a handle domain matches another configured site authority and the local part matches a non-disabled account of that site
- **THEN** the response returns that account's profile with `username` set and the handle derived from that site's canonical origin

#### Scenario: Stored remote Person
- **WHEN** a handle domain does not match a configured site and a stored remote Person has the same verified handle ignoring case
- **THEN** the response returns that Actor's profile with an empty `username` and the stored handle as `acct`

#### Scenario: Unknown handle without resolve
- **WHEN** a client requests an unknown handle without `resolve=1`
- **THEN** the server returns `404` and performs no outbound network request

#### Scenario: Blocked or disabled profile
- **WHEN** the resolved Actor is site-blocked, domain-blocked, site-banned, disabled, or personally blocked by the authenticated viewer
- **THEN** the server returns `404`

### Requirement: Authenticated remote profile resolution
`GET /api/v1/profiles/{acct}?resolve=1` SHALL require a valid current-site session
and SHALL return `401` when unauthenticated. It SHALL NOT perform discovery when the
handle domain matches a configured site authority; that case SHALL use local account
lookup only. For other domains it SHALL validate the handle, apply site block policy,
enforce a per-account or per-site rate limit, disable redirects, and use the existing
bounded federation fetch limits for both WebFinger and the Actor document. It SHALL
verify the WebFinger subject, the single matching ActivityPub `self` link, the Actor
identity, the `Person` type, the preferred username, and a canonical inbox before
persisting. A successful lookup SHALL return `200` with the same projection as a
handle read. A handle that cannot be verified SHALL return `404`. A rate-limited
request SHALL return `429`. A peer that cannot be reached within the configured
limits SHALL return `503`. A successful resolution SHALL upsert the verified handle
and public profile fields idempotently and SHALL NOT overwrite profile fields whose
stored `updated_at` is newer.

#### Scenario: Resolve a new remote account
- **WHEN** an authenticated user requests `?resolve=1` for a valid remote handle that is not stored
- **THEN** the server verifies WebFinger and the Actor document, stores the handle and profile fields, and returns the profile

#### Scenario: Resolve requires authentication
- **WHEN** an unauthenticated client supplies `resolve=1`
- **THEN** the server returns `401` and performs no network request

#### Scenario: Resolve a configured-site handle
- **WHEN** an authenticated user supplies `resolve=1` for a handle whose domain is a configured site authority
- **THEN** the server resolves only the local account and performs no outbound network request

#### Scenario: Resolution failure modes
- **WHEN** WebFinger or the Actor document fails verification, the request exceeds the rate limit, or the peer is unreachable
- **THEN** the server returns `404`, `429`, or `503` respectively and leaves existing profile data unchanged

### Requirement: Background remote profile bootstrap
Read paths that encounter a stored remote Person without a profile SHALL enqueue an
idempotent background bootstrap, including post search results, mention candidates,
and authors of received posts. Enqueueing SHALL NOT perform network discovery inline,
SHALL NOT block the response, and SHALL NOT change the response shape. Bootstrap work
SHALL reuse the existing actor handling worker, resolve the Actor document and
verified handle with the same bounded fetch policy as interactive resolution, and
persist the same fields through the same freshness rule. Bootstrap SHALL NOT alter
local accounts, install executable markup, fetch avatar bytes, or overwrite newer
profile data. Duplicate lookups for the same Actor SHALL collapse into at most one
pending job per site.

#### Scenario: Search result lacks a profile
- **WHEN** a post search result references a stored remote author without a profile
- **THEN** the search response is unchanged and one background bootstrap job is enqueued

#### Scenario: Received post author lacks a profile
- **WHEN** a received post is accepted from a remote Person without a stored profile
- **THEN** a background bootstrap job is enqueued without delaying acceptance

#### Scenario: Bootstrap cannot overwrite newer data
- **WHEN** background resolution produces profile fields older than the stored `updated_at`
- **THEN** the stored profile remains unchanged

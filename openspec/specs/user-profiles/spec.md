# user-profiles Specification

## Purpose

Provide editable public-facing profile information and avatars while preserving stable account identities and authoritative federation ownership.

## Requirements

### Requirement: Owner-edited public profiles
Users SHALL be able to read public profiles and edit their own display name, biography, and avatar using current-site sessions, same-origin checks, and CSRF. Fields SHALL have configured bounded lengths and sanitized display output. Avatars SHALL use validated owned image uploads and support removal. Username, Actor URI, email, credentials, and roles SHALL NOT be editable through this endpoint or exposed as private profile data. Public profiles and avatars SHALL be explicitly public irrespective of the visibility of posts their owners author. Disabled local accounts SHALL NOT accept edits.

#### Scenario: Avatar replacement
- **WHEN** an authenticated owner replaces an avatar with an owned valid image
- **THEN** subsequent profile reads show the replacement and another account cannot reuse the upload as its own avatar

### Requirement: Authoritative profile federation
Person representations SHALL include current display name, sanitized biography, and avatar metadata. Local profile changes SHALL issue authoritative Actor Update delivery to eligible followers. Remote profile changes SHALL require verified ownership of the unchanged Actor identity and SHALL respect freshness and block rules. A blank remote display name MAY be bootstrapped once from the canonical public Actor document's ActivityPub `name` after the document's identity is required to match the stored Actor URI; this bootstrap SHALL NOT overwrite a non-empty display name, SHALL NOT alter local profiles, SHALL NOT install executable markup, and SHALL NOT outrank a later verified Person update. Remote public avatars SHALL retain source URLs without server-side download, proxying, or caching. A remote update SHALL NOT alter local accounts or install executable profile markup.

#### Scenario: Forged or stale Actor update
- **WHEN** a sender attempts to update another Actor or an older profile update follows a newer one
- **THEN** the current authoritative profile remains unchanged

#### Scenario: Blank remote display name bootstrap
- **WHEN** a canonical public Actor document matching the stored Actor URI supplies a non-empty `name` and the remote profile has no display name
- **THEN** the blank display name is populated as sanitized plain text without fetching avatar bytes

#### Scenario: Bootstrap cannot overwrite authoritative data
- **WHEN** a remote profile already has a non-empty display name or is a local profile
- **THEN** public-document bootstrap leaves the existing display name unchanged

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


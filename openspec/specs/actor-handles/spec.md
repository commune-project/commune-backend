# actor-handles Specification

## Purpose

Provide a verified, persistent `username@domain` handle for post authors so browser clients can display a human-readable identity without guessing from Actor URI structure.

## Requirements

### Requirement: Verified actor handle storage

The system SHALL store a remote Person actor's handle in `actors.acct` only after the handle is verified through the actor's canonical public document and WebFinger. The value SHALL be the WebFinger `subject` with the `acct:` scheme removed, in `username@domain` form, without a leading `@`. Local Person handles SHALL be derived from the account username and the canonical authority of the account's site; they SHALL NOT be stored as inferred Actor URI path data. An unknown handle SHALL be the empty string. `acct` SHALL be display metadata only and SHALL NOT establish identity, ownership, authorization, or signature validity.

#### Scenario: Local handle derived from account identity
- **WHEN** a browser response includes a post authored by a local account `alice` at `https://forum.example`
- **THEN** the author handle is `alice@forum.example` without parsing `/users/alice` from the Actor URI

#### Scenario: Remote handle requires verification
- **WHEN** a received post names a remote Person whose Actor URI path contains a plausible username but no verified WebFinger handle is stored
- **THEN** `actors.acct` remains empty and the browser response does not invent a handle from the URI

#### Scenario: Handle cannot authorize
- **WHEN** a request presents or observes an `acct` value that differs from the stored Actor identity
- **THEN** the `acct` value grants no permission and the canonical `author_actor_uri` remains authoritative

### Requirement: First-encounter resolution jobs

When a site accepts content authored by a remote Person whose `actors.acct` is empty, the system SHALL durably enqueue at most one handle-resolution job for that site and actor. Enqueueing SHALL be part of the accepted-content transaction or otherwise atomic with the decision to store the content. Local Person actors, Group actors, and actors with a non-empty `acct` SHALL NOT enqueue jobs. Duplicate content replay SHALL NOT create duplicate jobs. Browser reads SHALL NOT enqueue jobs and SHALL NOT perform remote handle lookups.

#### Scenario: New remote author enqueues once
- **WHEN** a site receives its first post from a remote Person with an empty `acct`
- **THEN** one durable resolution job exists for that site and actor

#### Scenario: Replay is idempotent
- **WHEN** the same remote post is received again for the same site
- **THEN** the existing resolution job is retained and no duplicate job is created

#### Scenario: Browser read performs no lookup
- **WHEN** a browser reads a feed containing an author with an unresolved handle
- **THEN** the response is produced without a WebFinger request, Actor request, or job enqueue

### Requirement: Verified WebFinger resolution

A resolution job SHALL fetch the stored Actor URI using the controlled federation client and SHALL require a successful HTTPS response, a valid ActivityPub representation, no duplicate JSON keys, an `id` equal to the stored Actor URI, type `Person`, and a non-empty `preferredUsername`. It SHALL then request WebFinger for `acct:<preferredUsername>@<actor-authority>` and SHALL require the returned `subject` to match that account and exactly one ActivityPub `self` link whose `href` equals the stored Actor URI. Only when every check succeeds SHALL the system persist the verified `subject` as `actors.acct`. The system SHALL NOT derive the displayed handle from Actor URI path segments.

#### Scenario: Fully matching chain persists
- **WHEN** the Actor document identifies the stored URI with `preferredUsername: "bob"` and WebFinger returns `subject: "acct:bob@peer.example"` with a matching ActivityPub `self` link
- **THEN** `actors.acct` becomes `bob@peer.example`

#### Scenario: Mismatched identity is rejected
- **WHEN** the Actor `id`, `preferredUsername`, WebFinger `subject`, or `self` link disagree
- **THEN** no handle is stored and the existing empty value remains

#### Scenario: Custom-domain handle cannot be guessed
- **WHEN** the Actor authority cannot resolve the handle and the real handle uses another domain
- **THEN** the system leaves the handle empty rather than substituting the Actor URI authority or path

#### Scenario: Unsafe destination is refused
- **WHEN** the Actor URI, WebFinger URL, or a redirect resolves to a private, loopback, link-local, metadata, or non-HTTPS destination
- **THEN** the controlled fetch rejects the request before contacting the destination

### Requirement: Durable bounded resolution work

Handle-resolution work SHALL be leased, restart-recoverable, retried with bounded attempts and backoff, and terminally marked on success, permanent failure, or suppression. A worker SHALL recheck the current site block policy before fetching and SHALL suppress blocked actors without disclosing content. One actor's failure SHALL NOT block other jobs. The work SHALL use the existing configured federation time, byte, redirect, and destination limits, and SHALL NOT recursively enqueue additional remote work.

#### Scenario: Worker crash recovers work
- **WHEN** a worker claims a job and exits before marking it complete
- **THEN** the expired lease makes the job claimable again subject to its attempt limit

#### Scenario: Blocked actor is suppressed
- **WHEN** the receiving site currently blocks the actor or its domain
- **THEN** the job becomes suppressed and no remote request is made

#### Scenario: Exhausted attempts leave an empty handle
- **WHEN** every allowed attempt fails verification or retrieval
- **THEN** the job is marked failed and the browser continues to receive an empty `acct`

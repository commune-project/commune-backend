## MODIFIED Requirements

### Requirement: Author-authorized editing source
`GET /api/v1/posts/{id}/source` SHALL require a valid current-site session, current-site post reception and visibility, current community read access, current author editing authority, and a non-deleted post. It SHALL return `{id,title,body,updated_at,version}` with the stored title and body before display sanitization and a positive integer content version; untitled replies SHALL use an empty title. The version SHALL identify the same committed content snapshot as the source fields. `updated_at` SHALL remain informational and SHALL NOT substitute for the version precondition. It SHALL NOT promise restoration of whitespace already normalized during publication or editing. Anonymous requests SHALL return 401, missing/unreceived/hidden/unreadable/deleted resources SHALL return 404, and a readable post requested by a non-author SHALL return 403. An administrator SHALL NOT gain another author's source-editing authority through a management role. Source SHALL be JSON data for editor values, not executable HTML; ordinary display responses SHALL retain their sanitization boundary.

#### Scenario: Lossless edit values
- **WHEN** an authorized author requests source for a post containing markup, entities, and a title altered by display rendering
- **THEN** both source fields equal their stored values, the response includes their content version, and an unchanged edit with that version preserves those values subject to existing input normalization

#### Scenario: Membership revoked before source read
- **WHEN** a former member with a valid session requests source for their old post in an unreadable members-only community
- **THEN** the API returns 404 without source content

### Requirement: Private response handling and compatibility
Viewer-dependent responses, rosters, and source SHALL use `Cache-Control: no-store`. Existing display fields and mutation request contracts SHALL remain compatible except that author post PATCH SHALL require `expected_version` as specified by conditional author editing. New GET routes SHALL reject unsupported methods with 405 and an appropriate Allow header; existing mutation methods SHALL remain available on shared paths. Authorization or storage failures SHALL NOT be silently converted into successful empty pages or falsely denied capabilities. Existing stable error mappings SHALL remain in use, with explicit conditional-edit error mappings added.

#### Scenario: Unavailable authorization storage
- **WHEN** a read cannot determine current permission because required storage is unavailable
- **THEN** it returns an unavailable error rather than a successful anonymous or empty response

#### Scenario: Shared roster path retains mutation support
- **WHEN** a client uses existing member or manager POST/DELETE operations after roster GET support is added
- **THEN** existing authentication, CSRF, and authorization requirements remain enforced

#### Scenario: Legacy unconditional edit
- **WHEN** an authenticated author sends a post PATCH without `expected_version`
- **THEN** the server returns 400 and performs no edit, rather than falling back to unconditional overwrite

## ADDED Requirements

### Requirement: Conditional author editing
Author `PATCH /api/v1/posts/{id}` SHALL require a positive integer `expected_version` within the supported signed 64-bit range. Missing, null, non-integer, out-of-range, or non-positive values SHALL return 400 with the existing JSON error envelope. After current authentication, CSRF, visibility, authorship, and non-deleted-state checks succeed, the server SHALL atomically compare the expected version with the current content version and save only on equality. A mismatch SHALL return 409 with `{ "error": "edit_conflict" }` without current content or version disclosure. A successful edit SHALL return 200 with the saved content version and SHALL increment that version exactly once, including an accepted unchanged-content save. Successful browser post publication, edit, and import responses SHALL expose `version`. Conditional headers or `updated_at` SHALL NOT replace the required JSON precondition. Conflict responses SHALL use `Cache-Control: no-store`.

#### Scenario: Two drafts from one version
- **WHEN** two authorized editors read version 1 and submit edits with `expected_version: 1`, and the first save commits
- **THEN** the first response exposes version 2 and the second returns 409 with `error: "edit_conflict"`, leaving the first edit intact

#### Scenario: Simultaneous requests
- **WHEN** two valid PATCH requests with the same current expected version are submitted concurrently
- **THEN** exactly one commits and the other returns the documented conflict, with only one version increment

#### Scenario: Missing or malformed precondition
- **WHEN** an author submits missing, null, zero, negative, fractional, string, or out-of-range `expected_version`
- **THEN** the server returns 400 without changing content, attachments, mentions, or outgoing activities

#### Scenario: Stale request after access revocation or deletion
- **WHEN** an editor submits a well-formed stale version after losing edit access or after author deletion
- **THEN** existing authorization or not-found behavior applies before conflict disclosure and no content is returned

### Requirement: Content revision integrity and atomic failure
New and migrated posts SHALL have a positive content version. Accepted author edits, author deletion, and accepted inbound changes to editable content or deletion state SHALL advance the version atomically with the change. Content includes title, body, format, attachments, and mentions. Ignored inbound duplicates or older updates SHALL NOT advance it. Likes, replies to the post, read counters, and site-local visibility or moderation changes SHALL NOT advance its content version. Rejected conditional edits and failed saves SHALL leave content, version, attachment bindings, mentions, and transactional outgoing activities unchanged. A version SHALL NOT be reused for a later committed content state of the same post.

#### Scenario: Conflict involving attachments
- **WHEN** an editor submits a stale draft that replaces attachments and mentions
- **THEN** the server rejects it without altering text, version, attachment bindings, mentions, or outgoing Update activities

#### Scenario: Downstream save failure
- **WHEN** a matching-version edit fails attachment validation or transactional outgoing activity creation
- **THEN** the full edit including its version increment rolls back

#### Scenario: Other content writer invalidates draft
- **WHEN** another accepted content writer changes the same post after an editor fetched source
- **THEN** a subsequent authorized PATCH using the old version conflicts

#### Scenario: Interaction does not invalidate draft
- **WHEN** a post receives a like or a reply after an editor fetched source and its editable content is unchanged
- **THEN** that interaction alone does not cause a version conflict

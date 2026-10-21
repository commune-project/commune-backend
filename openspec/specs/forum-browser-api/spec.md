# forum-browser-api Specification

## Purpose

Provide complete browser-facing forum reads for discovery, discussion browsing, viewer actions, community administration, and lossless editing while preserving site and community access boundaries.

## Requirements

### Requirement: Paginated community discovery
`GET /api/v1/communities` SHALL return only readable communities hosted by the resolved site or remote communities represented by posts received by that site. Communities hosted by another colocated site SHALL NOT become discoverable merely through shared storage. Responses SHALL use `{items,limit,offset}`, default to limit 20 and offset 0, enforce configured maximum limits, return 400 for invalid pagination, and return an empty array for an empty page. Communities SHALL sort by name ascending then ID ascending. Authorization SHALL precede pagination. Anonymous readers SHALL see only public federated communities; local-only communities SHALL require eligible owning-site authentication or applicable audited administrative authority.

#### Scenario: Mixed community visibility
- **WHEN** an anonymous reader requests discovery at site A while public, members-only, local-only, and site-B-only communities exist
- **THEN** only site-A-scoped public federated communities appear, without restricted metadata or counts

#### Scenario: Authorized local discovery
- **WHEN** an authenticated owning-site user requests discovery
- **THEN** readable local-only communities appear alongside readable federated communities, with inaccessible communities excluded before pagination

#### Scenario: Invalid or exhausted pagination
- **WHEN** a reader supplies a zero, negative, excessive, or malformed limit, or a negative or malformed offset
- **THEN** the API returns 400, while a valid offset beyond available results returns 200 with `items: []`

### Requirement: Site-wide latest discussions
`GET /api/v1/topics` SHALL return paginated top-level posts ordered by authored time descending then ID ascending. It SHALL use the same pagination contract as community discovery. Every result SHALL have current-site reception, current read permission, and no author deletion, current-site hide, or removed/rejected community inclusion. These filters SHALL apply before pagination. The endpoint SHALL NOT import remote objects or disclose posts received only by another site.

#### Scenario: Shared storage does not imply reception
- **WHEN** sites A and B share storage and only B has received a remote topic
- **THEN** A's aggregate feed omits that topic

#### Scenario: Filtered latest page
- **WHEN** unreadable, hidden, deleted, removed, and rejected topics are newer than readable topics
- **THEN** the requested page contains the correctly ordered readable topics without counting excluded rows toward its offset or limit

### Requirement: Consistent post interaction metadata
All successful browser post representations, including topic/reply lists, detail, publication, editing, and import, SHALL include integer `like_count`, boolean `liked_by_me`, integer `reply_count`, and a `permissions` object. Active likes SHALL exclude undone reactions and represent the shared object's known active reactions, not a claim of complete federated totals. `reply_count` SHALL count only direct replies currently visible at the resolved site, excluding deletion, site hiding, and removed/rejected inclusion. Anonymous `liked_by_me` SHALL be false. Permissions SHALL expose `can_edit`, `can_delete`, `can_like`, `can_reply`, `can_hide`, and `can_moderate`, derived from the corresponding current mutation authorization and resource state; false capabilities SHALL be explicit.

#### Scenario: Like survives refresh
- **WHEN** an actor likes a readable post and subsequently reloads its detail or a containing list
- **THEN** `liked_by_me` is true and `like_count` counts that active like once; undo makes the state false and removes its contribution

#### Scenario: Reply count respects site visibility
- **WHEN** a topic has a hidden direct reply, an unreceived direct reply, a visible direct reply, and a nested reply
- **THEN** only the visible direct reply contributes to the resolved site's `reply_count`

#### Scenario: Anonymous and tombstone actions
- **WHEN** an anonymous reader receives a public post or an authorized reader receives a tombstone
- **THEN** unavailable actions are false and deleted content is not returned as editable source

### Requirement: Current viewer roles and community permissions
Successful login and session responses SHALL retain existing identity fields and add `roles` containing current `site_administrator` and `deployment_superadministrator` booleans. Community representations from creation, detail, and discovery SHALL add `viewer` containing `is_member`, `is_creator`, `is_manager`, and `management_scope`, and `permissions` containing `can_post`, `can_manage`, `can_manage_members`, and `can_manage_managers`. `is_manager` SHALL denote a current explicit community-manager assignment; creator status SHALL be separate. `management_scope` SHALL be one of the empty string, `community`, `site`, or `deployment`. Management authority SHALL NOT imply membership, authorship, or ordinary posting permission. Anonymous relationship flags and mutation permissions SHALL be false with empty management scope. Every request SHALL reflect current policy, membership, role, block, and account state; metadata SHALL NOT replace mutation checks.

#### Scenario: Administrative read without posting identity
- **WHEN** a site administrator without membership reads a hosted members-only community
- **THEN** management permissions are true, `is_member` is false, and `can_post` remains false

#### Scenario: Revocation with an existing session
- **WHEN** a user's role or membership is revoked while their session remains valid
- **THEN** the next response reflects the revocation or denies the read if access was lost, and subsequent unauthorized mutations fail

### Requirement: Management roster reads
`GET /api/v1/communities/{id}/members` and `GET /api/v1/communities/{id}/managers` SHALL require an authenticated identity with current community management authority at the hosting site. They SHALL use the discovery pagination contract and sort by actor URI ascending. Members SHALL include only non-revoked memberships. Managers SHALL contain the creator and non-revoked manager assignments, deduplicated by actor URI and marked with `is_creator` and `is_manager`. Rows SHALL expose `actor_uri` and SHALL NOT expose account email, credentials, or session data. Site/deployment administrators SHALL NOT be implicitly inserted into community rosters. Unknown or unreadable communities SHALL return 404, readable communities without management authority SHALL return 403, and unauthenticated roster requests SHALL return 401. GET SHALL NOT require CSRF or mutate membership; administrative reads SHALL preserve applicable audit requirements.

#### Scenario: Creator absent from assignment table
- **WHEN** an authorized manager reads a roster whose creator has no separate manager assignment
- **THEN** the creator appears once with `is_creator: true` and `is_manager: false`

#### Scenario: Ordinary member requests a roster
- **WHEN** an authenticated ordinary member without management authority requests either roster of a readable community
- **THEN** the server returns 403 without roster data

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

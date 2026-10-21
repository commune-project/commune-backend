## Context

See proposal.md for motivation. `internal/server/forum_posts.mygo` decodes a strict JSON edit input, resolves mentions, and wraps repository editing plus `QueuePostMutation` in an outer transaction. `internal/storage/post_edit.mygo` loads the row with `FOR UPDATE` through `MutateAuthor`, rechecks access, then modifies text and rich-content bindings. The lock already provides the serialization point but receives no editor revision. `internal/storage/posts.mygo` also updates shared records for accepted inbound federation changes. Existing source and compatibility requirements live in `forum-browser-api`.

## Goals / Non-Goals

**Goals:** Detect stale drafts across processes and shared-site storage using one authoritative revision; preserve atomicity with rich content and outgoing activities; retain existing security and site boundaries.

**Non-Goals:** Automatic merges, draft storage, collaborative editing, conditional DELETE, frontend implementation, and new ActivityPub conditional-write semantics. If-Match support is deferred; it does not replace the JSON requirement.

## Decisions

### 1. Persist a content revision

Add `posts.version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0)` through the next versioned migration and map it to an explicit signed 64-bit MyGO field. Existing records start at 1; timestamps and prior history remain intact. Revision is global to the shared post, not per site. Increment using database arithmetic under the content transaction. Overflow must fail and roll back rather than wrap or reuse a revision.

An integer revision avoids timestamp precision/collision issues. A hash adds canonicalization and attachment-order concerns. ETag/If-Match would require a new validator/header contract; JSON expected_version fits the strict existing edit input and response envelope.

### 2. Make the precondition mandatory

Decode `expected_version` with presence/type/range validation; missing/null and invalid integers return 400. Do not default it to the current revision or provide an unconditional fallback. Source returns version with the same stored snapshot; browser publication/edit/import projections expose the saved version. Keep updated_at informational. Conflict response is exactly HTTP 409 with `{"error":"edit_conflict"}` and no-store, fitting the existing error envelope without a second error-code field.

Authentication and CSRF remain enforced. For a syntactically valid edit, perform current site visibility, read/edit authorization and deletion checks before comparing versions. Do not disclose a version or current content on conflict; the client can separately request authorized source. Frontends retain drafts on conflict and choose how to merge; they must not fetch a new revision and automatically retry an old draft.

### 3. Compare inside the locked transaction

Thread the expected revision from PATCH to the content-edit operation. Inside the existing locked mutation callback, after authorization and non-deletion checks and before content/binding mutation, compare the locked record's version. Reject a mismatch immediately. Update text and increment version in the same transaction, then validate/update attachment and mention state and reload the saved record. Keep outgoing Update creation in the outer transaction. Avoid a handler-only comparison against `ReadObject`, which would race.

Audit mention resolution before the transaction: it may perform lookups, but rejected saves must not leave post-linked mention/binding or outgoing activity mutations. Any such mutations must move into the protected transaction. An error anywhere through outgoing activity creation rolls back both data and revision. No independently committed revision allocation is permitted.

### 4. Maintain every content writer

Audit all post and rich-content mutation paths. New local/imported posts use revision 1. Accepted author PATCH advances exactly once even if values normalize identically. Author deletion advances on the first transition; repeated deletion does not. Accepted inbound content/deletion updates advance once; duplicate/older events already rejected by existing ordering do not. Existing inbound authority/order checks remain authoritative; a remote sender never supplies our local revision. Ensure content, attachments and mentions from a single inbound update share one increment and transaction.

Repository convenience edit entry points must not silently bypass checking for browser saves. Tests/internal callers must provide the intended revision; any trusted inbound writer remains a separate authority-checked operation maintaining revisions. Likes, replies, site reception and moderation do not change the editor revision.

## Risks / Trade-offs

- [Breaking PATCH contract] → Coordinate client deployment, update API examples and every existing author-edit test; reject old requests explicitly.
- [Hidden rich-content or inbound writer bypass] → Inventory SQL and binding writes and add regressions for accepted versus ignored inbound updates and rollback.
- [Nested transaction behavior] → Verify against real PostgreSQL that repository errors and queue failures roll back the entire request.
- [JSON integer precision in some clients] → Document signed 64-bit integer handling; clients must preserve the token exactly and never coerce rounded values. Current frontend integration must verify its decoder can preserve the supported integer range.
- [Migration contention] → Apply through the existing explicit migration mechanism, assess production table lock time, and stop old writers before enforcing the contract.

## Migration Plan

1. Generate and test migration, revision-aware writers, responses, and strict PATCH contract together. Update browser API documentation and backend verification notes.
2. Coordinate frontend release so source versions are retained and supplied on saves. Inform existing API consumers of mandatory expected_version and 409 handling.
3. Pause/drain old server writers, back up the database, apply the additive migration, and deploy revision-aware servers and compatible clients before reopening writes. Mixed old/new writers are unsupported because old binaries do not advance revisions.
4. Verify source version, successful edit, and stale rejection on the deployed service. Preserve client drafts when saves fail.
5. Prefer a forward fix. If binary rollback is necessary, pause author writes; keep the additive column and revision values. Do not reopen unconditional editing while promising concurrency protection, and do not reset versions on redeployment.

## Why

Two editors can read the same post and both successfully save, allowing an older draft to silently overwrite a newer edit. The frontend's conflict recovery requirement is blocked because row locking and a source reread cannot detect stale drafts atomically.

## What Changes

- Add a persisted, monotonically increasing post content `version`, exposed in author source and successful browser post mutation responses.
- **BREAKING**: Require a positive integer `expected_version` on author PATCH requests; reject missing or invalid values with 400 and stale values with 409 and stable `edit_conflict` identification.
- Compare versions under the existing transaction and row lock before content changes, and advance the version atomically on accepted edits.
- Cover content, attachments, mentions, and outgoing activity creation in the conflict rollback boundary; maintain revisions across other content writers.
- Document coordinated client rollout and executable PostgreSQL concurrency acceptance.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `forum-browser-api`: Extend editing source and mutation contracts with mandatory atomic version checks, conflict responses, and an explicit exception to mutation request compatibility.

## Impact

Post schema and migrations, post records and content write paths (including inbound federation), browser source/projections, PATCH decoding and error mapping, transaction/outbox integration, MyGO tests and generated Go, and browser API documentation. Existing clients must fetch source versions and send them on PATCH before deployment; frontend implementation remains outside this backend change. No new dependency or ActivityPub wire-level version requirement is introduced.

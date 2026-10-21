## 1. Persist and maintain content revisions

- [x] 1.1 Inventory post SQL, attachment/mention writers, repository edit callers, and inbound update paths; record their revision behavior in verification notes and verify every content writer has a mapped transaction boundary.
- [x] 1.2 Add the next explicit migration and typed post revision mapping; verify fresh and existing PostgreSQL databases initialize version 1 without changing content/timestamps and reject non-positive revisions.
- [x] 1.3 Add required expected revision parameters to author-edit repository entry points and compare under the existing row lock after authorization; verify matching saves increment once, unchanged saves increment once, and stale saves preserve the committed record.
- [x] 1.4 Maintain revisions on initial creation/import, first author deletion, and accepted inbound content/deletion updates; verify duplicate/older inbound events and repeated deletion do not increment, while likes/replies/site moderation leave revisions unchanged.

## 2. Expose and enforce the browser contract

- [x] 2.1 Add version to source snapshots and successful browser publication/edit/import responses; verify source fields and version are read consistently and existing display fields remain available.
- [x] 2.2 Decode mandatory positive signed 64-bit expected_version on PATCH and thread it to storage; verify missing, null, zero, negative, fractional, string, and overflow inputs return 400 and headers/timestamps cannot bypass the requirement.
- [x] 2.3 Map stale saves to 409 with exactly the error value edit_conflict and no-store; verify valid stale requests still respect CSRF, revoked access, site visibility, authorship and deletion checks before conflict disclosure.
- [x] 2.4 Ensure attachment/mention mutation and outgoing Update creation share the protected transaction; verify stale saves and induced downstream validation/queue failures leave text, revisions, bindings, mentions and outgoing activity rows unchanged.

## 3. Verify concurrency and integration

- [x] 3.1 Add real PostgreSQL tests for sequential two-draft saves and synchronized concurrent requests using independent transactions/connections; verify exactly one 200, one 409, one revision increment and the winning content.
- [x] 3.2 Add regressions for rich-content conflict rollback, accepted versus ignored inbound revisions, deletion/access revocation, revision overflow rollback, and interaction independence; verify the relevant storage/server suites pass.
- [x] 3.3 Update existing author-edit tests and fixtures to obtain and submit real versions; regenerate Go using the project generator and verify make generate, make build, make test and make test-postgres with bounded runtime/memory and a task-local writable GOCACHE, recording any external validation blockers explicitly.

## 4. Document and review the contract

- [x] 4.1 Update browser API documentation with source/PATCH/success/conflict examples, integer handling, draft-preserving recovery, and the breaking missing-version behavior; verify examples agree with executable contract tests.
- [x] 4.2 Update verification notes with writer coverage, concurrency/rollback evidence, coordinated client deployment and paused-write rollback instructions; verify no mixed old/new writer rollout or automatic stale-draft retry is prescribed.
- [x] 4.3 Review completed implementation against every delta scenario and run openspec validate add-post-edit-concurrency-control --strict; verify acceptance evidence distinguishes PostgreSQL tests from any unavailable live deployment checks.

## 1. Current authorization and read projections

- [x] 1.1 Add reusable current-viewer community and post permission projections aligned with actual mutation predicates; verify anonymous, member, creator, assigned manager, site administrator, deployment administrator, blocked actor, and deleted-post cases with focused policy tests.
- [x] 1.2 Make affected optional-authentication reads distinguish anonymous/invalid sessions from storage failures; verify invalid or cross-site sessions grant no identity and unavailable authentication/authorization storage produces an unavailable response.
- [x] 1.3 Extend login/session identity output with current site/deployment role booleans; verify existing identity fields remain and role revocation takes effect with an unchanged session.

## 2. Community discovery and aggregate topics

- [x] 2.1 Implement readable site-scoped community candidates and deterministic name/ID pagination; verify hosted, received-replica, local-only, restricted, blocked, and unrelated colocated-site cases in PostgreSQL, including filtering before offsets.
- [x] 2.2 Add GET community collection handling and enriched community DTOs for creation/detail/list; verify viewer relationship flags, management scope, independent posting permissions, empty arrays, invalid pagination, no-store, and retained POST behavior over HTTP.
- [x] 2.3 Implement current-site latest-topic queries with authored-time/ID ordering and all access/inclusion exclusions before pagination; verify hidden, deleted, removed, rejected, unreceived, and unreadable rows cannot affect page contents or offsets.
- [x] 2.4 Add GET /api/v1/topics using existing pagination bounds; verify anonymous public access, authorized local-only access, 400 invalid pages, empty pages, 405/Allow, and privileged-read auditing over HTTP.

## 3. Post metadata and complete response paths

- [x] 3.1 Add batched active-like counts, viewer reaction state, and visible direct-reply counts; verify like/undo idempotency and exclusion of hidden, unreceived, deleted, removed/rejected, and nested replies from direct counts in PostgreSQL.
- [x] 3.2 Use one enrichment path for detail, topic/reply lists, creation, editing, and import responses; verify every path emits all counts and permission booleans while preserving safe rendered title/body and existing fields.
- [x] 3.3 Verify enrichment uses bounded batch queries with page-size comparisons and representative PostgreSQL query plans; add versioned indexes only if evidence shows they are needed and record the evidence.

## 4. Management rosters

- [x] 4.1 Add paginated active-member and deduplicated creator/manager projections ordered by actor URI; verify revoked entries disappear, creator-only and creator-plus-manager flags are correct, and higher-scope administrators are not inserted automatically.
- [x] 4.2 Dispatch roster GET separately from CSRF-protected POST/DELETE; verify 401 anonymous, 404 inaccessible, 403 readable non-manager, successful audited manager reads, no-store, pagination, Allow headers, privacy of row fields, and unchanged mutation CSRF enforcement.

## 5. Editing source

- [x] 5.1 Add GET /api/v1/posts/{id}/source with current reception/visibility, read, authorship, and non-deleted checks; verify 401/403/404 distinctions, administrator non-author denial, cross-site isolation, revoked-member denial, and no-store.
- [x] 5.2 Return stored title/body plus ID and updated_at without display conversion; verify markup/entity/title round trips and untitled replies while ordinary display responses remain sanitized and deleted content is unavailable.

## 6. Documentation and integrated verification

- [x] 6.1 Publish browser API endpoint and JSON examples covering pagination, all viewer/permission fields, roster visibility, known-like/direct-reply count semantics, source usage, and errors; update authentication documentation and verify examples against HTTP acceptance tests.
- [x] 6.2 Run a combined multi-site PostgreSQL acceptance matrix covering all new reads, role/membership/policy revocation, administrative audits, and unchanged mutation authorization; record commands and results with no claims of untested live federation behavior.
- [x] 6.3 Regenerate affected Go from MyGO using existing Makefile generation order and run make build, make test, and make test-postgres with bounded time/memory and writable task-local Go caches; verify generated files are compiler output and review all failures before marking complete.
- [x] 6.4 Run openspec validate complete-forum-frontend-api --strict and review the final diff for API-contract consistency and unrelated changes; verify every completed task has its stated evidence before proposing archive.

## Context

See proposal.md for motivation and specs/forum-browser-api/spec.md for the browser contract. Existing MyGO repositories separate shared posts from `site_posts`, keep raw stored content separate from `RenderText`, and calculate community access from current membership and management authority. Server DTO conversion currently accepts only a record, so it cannot supply viewer metadata. Authentication responses currently expose identity without roles. The existing shared-forum-objects and site-isolation specs remain authoritative.

## Goals / Non-Goals

**Goals:** Reuse current authorization decisions across reads and mutations; produce complete list/detail/mutation representations; filter before pagination; bound enrichment queries by page size; keep administration auditable.

**Non-Goals:** No federation-wide discovery or total-count guarantees, remote-roster proxying, new role-assignment semantics, content-format conversion, cursor pagination, or new dependencies. Product features deferred in the proposal remain outside this change.

## Decisions

### 1. Add a browser capability without rewriting baseline specs

Create one additive `forum-browser-api` spec. Baseline requirements describe access and isolation but not these concrete contracts. A separate capability avoids duplicating or weakening them. No changes to the archived implementation plan are needed.

### 2. Project current access into explicit viewer DTOs

Introduce read projections that carry records plus current access, interaction aggregates, and per-viewer state. Keep content rendering at the server output boundary. Use shared authorization predicates for capabilities and writes; evaluate post state as well as actor authority. An empty management scope means no authority. `is_manager` is an explicit assignment, while creator and effective management scope remain separate. Resolve site/deployment roles on each login/session response instead of embedding them in session tokens.

Anonymous input is a valid subject, but authentication-storage errors must propagate. Replace the existing optional-identity error collapse in affected browser reads with a result that distinguishes absent/invalid credentials from unavailable storage. Never return successful anonymous metadata when role resolution fails. Viewer responses use no-store, including anonymous variants, to keep response handling uniform.

Alternative: frontend derivation from roles or policy strings. Rejected because site blocks, authorship, eligibility, administrative overrides, and revocation would diverge from actual authorization.

### 3. Filter the site-scoped candidate set before paging

For discovery, candidates are communities hosted by the selected site plus non-hosted replicas linked to its received posts. Shared rows belonging to another hosted site are not discovery candidates. Include authenticated local-only communities under the existing access policy; they remain absent from public discovery.

For aggregate topics, start with current-site reception and top-level posts. Reuse the existing feed exclusion rules for deletion, hiding, and removed/rejected inclusion. Apply current readable-community predicates before ORDER/LIMIT/OFFSET. Use correlated EXISTS or joins with deduplication so relationships cannot multiply rows. Keep SQL eligibility behavior aligned with ordinary access checks using a shared policy model and table-driven parity tests; do not fetch all rows and filter them in application memory. Preserve existing administrative audit semantics for privileged reads, including discovery/feed reads that rely on an override.

Order communities by name/ID ascending and topics by authored time descending/ID ascending. Reuse limit/offset parsing and configured bounds. No total count is added. Offset pagination is compatible with existing endpoints but does not guarantee a snapshot across concurrent inserts.

Alternative: concatenate existing per-community pages. Rejected because it produces incorrect global order and offsets and scales with the entire community set.

### 4. Enrich all post-producing browser paths in batches

Collect page post IDs and community IDs, resolve access in batches, group active reaction counts, select current actor reaction existence, and group direct visible reply counts. Use the same enrichment for single-record publication/edit/import responses. Query count must not grow linearly per post; a page of 20 posts must not cause 20 individual reaction/access queries.

Likes are shared known-object reactions with `undone_at IS NULL`. This matches the existing shared reaction model; it is not a remote-global count. Reply totals are deliberately site-specific and use the same access/inclusion rules as reply listing. A deleted post may retain its existing tombstone representation but never reports edit/reply/like as available. Local API permissions must reflect actual route capabilities, including the inability to perform hosted-community mutations against a remote replica. Predicate drift discovered between existing mutation routes must be repaired within the affected authorization path, not hidden with optimistic booleans.

Alternative: counters stored on posts. Rejected initially because revocation and site-specific visibility make shared counters misleading and require new consistency machinery.

### 5. Extend roster paths without applying mutation requirements to GET

Dispatch GET before `RequireMutation`, authenticate without CSRF, then load hosted community access and require management authority. Keep POST/DELETE on the existing mutation path. Query non-revoked members; union creator and non-revoked moderator assignments for managers, deduplicate, then sort and page. Return only actor URI and the specified identity flags. These are hosted community rosters, not replicas' potentially incomplete authority lists. Use scoped administrative audit handling without changing memberships.

Alternative: expose public rosters or proxy remote authority lists. Deferred because neither is required to populate the local management screen and both change disclosure/trust scope.

### 6. Add a separate source read

Dispatch `/posts/{id}/source` as a read requiring a session. Reuse current-site reception/visibility and current read checks before author authorization; reject deleted content. Return raw stored title/body and version timestamp as JSON. Keep the ordinary `body` and `title` display behavior unchanged. Source is an editor value and must never be rendered as trusted HTML. Administrative privileges cannot substitute for author rights.

Alternative: include raw source in all post DTOs. Rejected because it distributes unused raw content to lists and ordinary readers and blurs the display/edit contract. Restoring pre-normalization whitespace or introducing optimistic concurrency is outside scope; `updated_at` provides version context only.

## Risks / Trade-offs

- SQL/read and mutation authorization divergence → shared policy predicates and parity tests covering anonymous, local, remote, members, blocks, role scopes, and revocation.
- Cross-site or restricted metadata leakage → candidate scoping and authorization before pagination; independent-site fixtures for every read and count.
- Aggregates become expensive → bounded batch queries, query-count checks, realistic PostgreSQL plans; add indexes only if evidence warrants a migration.
- Personalized cache contamination → explicit no-store on all affected browser responses.
- Concurrent state changes during reads → keep each response's access and aggregates coherent with a read transaction where needed; every later mutation rechecks authorization.
- New source reads encounter historical lossy storage → promise stored values only; test markup/entity/title preservation and existing normalization.

## Migration Plan

1. Implement projections, routes, tests, and API examples in MyGO; regenerate all affected Go using existing Makefile targets.
2. Run focused HTTP and real PostgreSQL acceptance checks followed by required build/test checks. No data backfill is expected. If query evidence requires an index, add it through the versioned migration mechanism.
3. Deploy the additive backend contract before enabling the frontend screens. Existing consumers continue using their current fields and mutation routes.
4. Roll back the backend binary and corresponding frontend feature use if necessary; additive response fields introduce no data rollback. Any optional index migration follows the project's normal migration policy.

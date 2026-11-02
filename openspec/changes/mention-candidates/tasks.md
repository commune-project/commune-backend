## 1. Storage candidate query

- [ ] 1.1 Add the mention candidate record, repository entry point, query validation for 2–64 Unicode scalar values, and limit validation for 1–20 in a focused storage module; verify `mygo sync internal/storage` regenerates the package and `go test -run '^$' ./internal/storage` succeeds.
- [ ] 1.2 Implement one parameterized candidate query that unions resolved-site accounts, stored remote Persons with a non-empty handle, and Persons local to another configured site with a derived handle; deduplicate by Actor URI, apply self/disabled/site-block/site-ban/viewer-block filters, rank prefix matches first, and apply the limit after ordering; verify the query with a Postgres storage test.
- [ ] 1.3 Add `internal/storage/mention_candidates_test.mygo` covering local, stored remote, colocated-site, missing-handle, display-name fallback, empty avatar, block/ban/self/disabled exclusion, literal wildcard escaping, prefix ordering, stable tie-breaking, and limit enforcement; verify `go test ./internal/storage -run TestPostgresMentionCandidates` passes.
- [ ] 1.4 Confirm the storage query performs no writes and does not enqueue actor-handle or delivery work by asserting relevant row counts remain unchanged; verify the same focused storage test passes.
- [ ] 1.5 Leave mention parsing and activation untouched: do not edit the existing remote-discovery path or local-handle resolution; verify the existing rich-post and mention tests still pass.

## 2. Browser route and response

- [ ] 2.1 Add the mention candidate response DTO and an authenticated `GET /api/v1/mentions/candidates` route that sets `Cache-Control: no-store` and `Referrer-Policy: no-referrer` before validation, requires a session, validates `q` and `limit`, accepts `community_id` without using it for filtering or access checks, and maps errors to `400`, `401`, `405`, or `503`; verify the route test covers each status.
- [ ] 2.2 Register the route in the browser participation dispatch before other browser reads and confirm it does not shadow search, profile, or post reads; verify existing route tests still pass.
- [ ] 2.3 Add `internal/server/mention_candidates_test.mygo` covering anonymous rejection, invalid query and limit, method rejection, response headers, local and remote items, optional `community_id` producing the same items, and the absence of new actor-handle or notification rows; verify `go test ./internal/server -run TestMentionCandidates` passes.
- [ ] 2.4 Run `mygo sync internal/server`, confirm generated files are regenerated rather than hand-edited, and verify the focused server tests pass.

## 3. Documentation and final verification

- [ ] 3.1 Document the endpoint in `docs/participation-api.md` and `docs/api.md`, including optional `community_id`, the response fields, the no-network rule, and the frontend note that local `@username` and remote `@username@domain` are both valid; verify the examples match the implemented response.
- [ ] 3.2 Run `openspec validate mention-candidates --strict` and confirm the change has no validation errors.
- [ ] 3.3 Run `go test ./...` and `make test-postgres`; confirm the new storage and route tests pass together with the existing suite.
- [ ] 3.4 Review the final diff for unexpected files, hand-edited generated code, or changes to mention activation; verify only the intended storage module, route, DTO, tests, generated files, documentation, and OpenSpec artifacts changed.

## 1. Conventions and shared foundations

- [x] 1.1 Write `docs/mygo-style.md` covering pattern versus constructor qualification, exhaustive switches with guarded fallbacks, prelude-first collection processing, impl ownership, typeclass criteria, and the allowed inline-Go list; verify every rule cites a concrete example from the repository.
- [x] 1.2 Add a MyGO-only helper package with `Sequence` (and `Collect` if a second shape is needed) for `Slice[Result[A, E]]`, implement it with `Fold` and `Result.AndThen`, and verify unit tests cover all-ok, first-error, and empty input.
- [x] 1.3 Add the `Failure` ADT with `InvalidField`, `ConflictKind`, `LimitKind`, and `UpstreamKind` sub-enums, plus total `Parse`/`Render`/`Status` functions; verify tests assert the exact current message and status pairs for every constructor.
- [x] 1.4 Replace the `FailStatus` string ladder with the `Failure` mapping while callers still pass strings, and verify the full server suite still returns identical codes and bodies.
- [x] 1.5 Add `WithActor`, `WithJSON`, and `Complete` helpers over concrete `Result[(), Failure]` signatures, and verify one converted route reproduces its current success and error responses.

## 2. Leaf packages: content, config, auth

- [x] 2.1 Introduce `ContentFormat` and `ObjectType` in `internal/content` with boundary parse/render, and verify `content` tests plus post rendering tests pass unchanged.
- [x] 2.2 Convert `BuildRendering` validation to a rule list folded into `Result`, and verify the participation configuration tests still reject every invalid allowlist case.
- [x] 2.3 Convert `ParticipationDefaults` to per-group reconstruction functions and verify defaults tests cover every field that currently defaults.
- [x] 2.4 Introduce `FederationMode`, `ReadPolicy`, and `PostPolicy` in `internal/auth`, parse them at `CommunityPolicy` construction, and verify `Valid`/`CanRead`/`CanPost` become exhaustive switches with policy tests unchanged.
- [x] 2.5 Convert the remaining `internal/auth` flows (`identity`, `tokens`, `verification`, `password_reset`) to `switch` and `Result` pipelines, and verify the auth test suite passes.
- [x] 2.6 Move the sanitizer allowlist constants and `rich.mygo` condition chains onto exhaustive switches and `let` bindings, and verify rich rendering and separation tests pass.

## 3. Storage layer

- [x] 3.1 Collapse `QueryFailed`/`MutationResult` usage into `Result`-returning query helpers, and verify `go test ./internal/storage/first -run` compile-only plus the storage suite pass.
- [x] 3.2 Convert repository methods to `Result[T, Failure]` with no message strings, and verify each repository test asserts the same failure classification as today.
- [x] 3.3 Rewrite `delivery_plan` and `receipts` accumulator loops with `Sequence`/`Fold`, and verify the delivery and receipt tests preserve job/receipt counts and failure short-circuiting.
- [x] 3.4 Replace `ThreadBefore`/sort and stats lookups in `browser` storage paths with keyed `Map.FromPairs` lookups, and verify the thread and browser storage tests pass.
- [x] 3.5 Rewrite `MediaSafeName` and `MediaFileID` in pure MyGO with prelude string/slice operations, and verify the media file tests cover control characters, separators, length limits, and dot names.
- [x] 3.6 Move record-side derivations into `impl` blocks on the owning records, and verify no cross-package `impl` remains by grepping for foreign receiver types.

## 4. Federation layer

- [x] 4.1 Convert collection parsing and traversal to switches over a collection-kind ADT with guards, and verify traversal tests cover collection, ordered collection, page, and invalid documents.
- [ ] 4.2 Rewrite context, representation, and profile parsing to `Result` pipelines and prelude combinators, and verify the federation unit suite passes.
- [ ] 4.3 Reshape signature and key-assert code with exhaustive switches while keeping crypto and PEM handling in Go FFI, and verify signature and keyassert tests pass.
- [ ] 4.4 Rewrite fetch and media-fetch result handling without nested early returns, and verify media fetch and fetch tests pass.

## 5. Server layer

- [x] 5.1 Convert the route dispatchers (`Handler`, `ForumRoute`, `CommunityRoute`, `PostRoute`) to switch-with-guards over segment tuples, and verify routing tests plus method-not-allowed tests pass.
- [ ] 5.2 Convert every handler to `WithActor`/`WithJSON`/`Complete` and delete the remaining `FailStatus` string comparisons, and verify the server suite passes with no `IsErr()` pyramid above two levels.
- [x] 5.3 Replace `SortThread` with a stable `SortedBy` comparator over a `ThreadSortMode` ADT, and verify the four ordering-mode tests produce identical orderings.
- [x] 5.4 Refactor `BrowserPosts` and `BrowserThread` to keyed lookups and `ZipWith`, and verify browser feed, thread depth, and media rendering tests pass.
- [x] 5.5 Move projections into `impl`/static constructors that live beside their DTOs, and verify JSON golden-shape tests are unchanged.
- [ ] 5.6 Convert notifications, moderation, search, votes, and federation handlers to the same shape, and verify their focused test files pass.

## 6. Entry point and verification

- [x] 6.1 Convert `cmd/commune/main.mygo` to the same conventions, and verify `mygo build cmd/commune` succeeds with regenerated output.
- [x] 6.2 Record the ADT boundary rules and the current compiler constraints in `docs/compiler-migration-issues.md`, and verify the notes match the shipped code.
- [ ] 6.3 Run `make test` and verify all packages pass with regenerated `zz_*.gen.go` files.
- [ ] 6.4 Run `make test-postgres` and verify the PostgreSQL-specific suites pass.
- [ ] 6.5 Run `make verify-protocol` and `make verify` and verify wire snapshots and generated-file determinism hold.
- [x] 6.6 Compare current and resulting metrics (lines containing `if` versus `switch`, `Unwrap()` count, `IsErr()` count, enum count, typeclass impl count) and verify the refactor produced the intended shift recorded in the change summary.


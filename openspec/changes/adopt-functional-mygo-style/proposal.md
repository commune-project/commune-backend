## Why

The MyGO sources under `internal/` and `cmd/` are written in an imperative Go
shape: across 21k non-test lines there are roughly 2,447 lines containing `if`
but only 35 containing `switch`, 1,100 `IsErr()` checks, 1,000 `Unwrap()` calls,
266 GORM result checks, zero `enum` declarations, and zero typeclass impls.
Domain invariants therefore live in string literals ("members", "federated",
"not found"), error classes are reconstructed by a 60-line `if` ladder in
`FailStatus`, and collection work is often a hand-rolled `while` loop or an
`Each` callback mutating `var` accumulators, including an O(n^2) selection sort
and repeated `Filter(...).Get(0)` lookups.

MyGO already provides algebraic data types with exhaustive pattern matching,
guards, prelude collection combinators, and `impl`/typeclass dispatch. The
repository now pays the cost of not using them: refactors cannot rely on
exhaustiveness, invalid policy combinations are representable, and equivalent
logic is duplicated across handlers. This change applies those features
consistently, and the project owner has approved a large-scale ADT migration
provided externally observable behavior is preserved.

## What Changes

- Introduce in-process ADTs for domain values that are currently strings:
  failure classification, federation mode, read/post policy, community follow
  policy and state, content format, object type, thread sort mode, delivery
  state, and moderation/report state, with explicit parse and render functions
  at configuration, JSON, and persistence boundaries.
- Move repository, federation, and handler results to typed failures
  (`Result[T, Failure]`) where the caller decides the HTTP outcome, and derive
  both the status code and the public message from one exhaustive mapping.
  Public error strings, status codes, and response shapes stay byte-identical.
- Replace `var` accumulators, index `while` loops, and early-return ladders with
  prelude combinators (`Map`, `Filter`, `Fold`, `Any`, `All`, `Find`,
  `SortedBy`, `ZipWith`, `Partition`, `Map.FromPairs`) plus a small shared
  `Sequence`/`Collect` helper for `Slice[Result[A, E]]`.
- Convert repeated per-handler request plumbing into `WithActor`/`WithJSON`/
  `Complete`-style helpers so handlers read as a flat sequence of typed steps.
- Organize projections and policy decisions as `impl` methods on the type that
  owns them, and add typeclass impls only where generic consumers exist
  (`Ord` for thread ordering, `ToString`/status mapping for failures,
  `Default` for configuration groups, `Validatable` for rule tables).
- Remove business logic that currently sits in inline `go[...]` blocks (media
  filename sanitization, media id validation) and express it with prelude
  string/slice operations; keep inline Go only for Go-only boundaries such as
  `defer`, nil comparison, `select` on cancellation, and variadic forwarding.
- Record the resulting conventions in `docs/mygo-style.md` so new code and the
  in-flight `profile-acct-lookup` change follow the same rules.

## Capabilities

### New Capabilities

None. This is a pure internal refactor: no requirement in any existing
capability changes, and no new externally observable behavior is introduced.

### Modified Capabilities

None. The change preserves every documented status code, error message,
response shape, storage schema, and federation wire format.

## Impact

- Affected code: `internal/config`, `internal/auth`, `internal/content`,
  `internal/storage`, `internal/federation`, `internal/server`, `cmd/commune`,
  plus the checked-in `zz_*.gen.go` generation output.
- New shared code: a small combinator/route-helper surface (MyGO only), and
  `docs/mygo-style.md` as the convention reference.
- Unaffected externally: HTTP API, ActivityPub payloads, PostgreSQL schema and
  migrations, configuration file format, Docker images.
- Coordination: `openspec/changes/profile-acct-lookup` is still unimplemented
  and touches `storage/profiles`, `server/profiles`, and `federation`; module
  ordering must avoid overlapping edits.
- Verification stays on the existing matrix: `make test`, `make test-postgres`,
  `make verify-protocol`, plus `make verify` for generated-file determinism.


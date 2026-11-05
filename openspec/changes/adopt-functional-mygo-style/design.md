 ## Context

 See `proposal.md` - Why for motivation. Constraints that shape the approach:

 - Non-test sources are ~21k MyGO lines across 31 package paths; ~18.5k lines of
   tests already pin current HTTP, storage, and federation behavior.
 - `zz_*.gen.go` is checked in and `make verify` asserts regeneration is
   deterministic, so every module lands with a fresh `sync` and no manual edits.
 - The prelude comes from the released module `github.com/mygo-lang/mygo
   v0.2.0-beta1`, not from this repository; adding prelude functions requires a
   release or a temporary `replace`.
 - `openspec/changes/profile-acct-lookup` is unimplemented and will touch
   `storage/profiles`, `server/profiles`, and `federation`.

 Compiler facts verified with a compiler built from the current `mygo` worktree
 (probe packages under `/tmp`, not part of this change):

 - Enum switches are checked for exhaustiveness: a missing variant fails with
   `non-exhaustive switch: missing variant(s) ...`. A guarded case does not
   count as coverage, so guarded branches need an unguarded fallback.
 - Patterns are unqualified (`case Open =>`), while constructors in expression
   position are qualified (`Policy.Open`, `Failure.Invalid("x")`). Writing
   `case Policy.Open =>` is accepted today and degrades to an always-true
   branch; this style must never be used, and a compiler diagnostic would help.
 - Enums lower to a Go interface plus variant structs, so they cannot be JSON
   or GORM field types; they are in-process values with explicit boundary
   conversion.
 - Cross-package `impl` blocks are silently dropped (MyGO accepts them, generated
   Go has no methods), so impl ownership follows package ownership.
 - Typeclass methods are called with receiver syntax (`failure.Status()`); they
   are not free functions.
 - A function-typed parameter whose result is `Result[U, E]` with generic `U`
   fails inference (`cannot unify Int with String`), so a fully generic
   `Traverse` is not writable yet; `Sequence[T](Slice[Result[T, String]])` is.
 - `case ... then` block bodies close with their own `end`, and all switch
   branches must share one result type (`fmt.Println` needs a `let _ =`).

 Prelude already covers `Map`, `Filter`, `Fold`, `Find`, `Any`, `All`,
 `Partition`, `Zip`/`ZipWith`, `Sorted`/`SortedBy`, `Distinct`, `Take`/`Skip`,
 `Map.FromPairs`/`Keys`/`Values`, and `Result.AndThen`/`Map`/`MapErr`/
 `MapWithOk`. Missing pieces are `Sequence`/`Traverse`, aggregated grouping,
 and a few string predicates.

 ## Goals / Non-Goals

 **Goals:**

 - Make illegal domain states unrepresentable in the layers that decide policy:
   community access, federation mode, content format, follow state, thread
   ordering, delivery state, and error classification.
 - Give every branch of domain logic one obvious shape: pattern match on an ADT
   with exhaustive cases and guards instead of chained string comparisons.
 - Make cross-layer composition read as data flow: `Result` pipelines and prelude
   combinators rather than mutable accumulators and nested early returns.
 - Land the migration in independently revertible module-sized steps with the
   existing acceptance suites as the oracle.

 **Non-Goals:**

 - No change to HTTP routes, request/response JSON, status codes, public error
   strings, ActivityPub documents, or the PostgreSQL schema.
 - No new runtime dependency, no hand-written Go package (aside from the existing
   embed/test transport files), and no change to the frontend submodule.
 - No rewrite of the build system, generation flow, or test strategy.
 - No prelude release in this change; prelude gaps are filled locally and
   reported for a later upstream change.

 ## Decisions

 ### 1. ADTs are in-process values; boundaries stay explicit strings

 Each migrated concept gets an `enum` in the package that owns the invariant
 (for example `auth.FederationMode`, `auth.ReadPolicy`, `auth.PostPolicy`,
 `auth.Failure`, `storage.ContentFormat`, `server.ThreadSortMode`). Records and
 wire structs keep `String` fields, and every crossing point uses a total parse
 function returning `Result[ADT, Failure]` plus a total render function.

 Alternatives: adding JSON/GORM marshalling to enums (the Go lowering is an
 interface plus variant structs, so it would need generated adapters); newtype
 aliases over `String` (no exhaustiveness, no pattern matching). Rejected: the
 boundary conversion is exactly where validation belongs, and it keeps the
 schema and API types untouched.

 ### 2. One failure ADT, layered by responsibility

 `auth.Failure` (or a small `internal/failure` package if import cycles appear)
 carries domain-level classification, not messages:

 - `Unauthenticated`, `Forbidden`, `NotFound`, `FeatureDisabled`,
   `Unavailable`, `NotReady`
 - `Invalid(InvalidField)` where `InvalidField` is its own enum
 - `Conflict(ConflictKind)` where `ConflictKind` is its own enum
 - `RateLimited(LimitKind)`, `Upstream(UpstreamKind)`

 Storage and federation return `Result[T, Failure>`; handlers only decide how to
 render. One exhaustive `Failure → (status, message)` mapping replaces the
 `FailStatus` string ladder, and it must reproduce the current pairs exactly
 (for example `NotFound → 404 "not found"`, `Forbidden → 403 "forbidden"`,
 `Conflict(Version) → 409 "edit_conflict"`).

 Alternatives: keep `Result[T, String]` and treat strings as implicit codes
 (no exhaustiveness, every new code silently falls into 503); keep strings at
 repository level and classify only in handlers (duplicated classification, the
 403/404/409 distinctions stay in `if` chains). Rejected given the explicit
 approval for a large-scale ADT migration.

 ### 3. Prelude first, local combinators second, Go FFI only at boundaries

 Collection work uses prelude methods directly. The one routinely missing
 combinator is `Sequence`, which is implemented in a small MyGO-only helper
 package (working form verified: `Fold` over `Result[Slice[T], String]` with the
 element type anchored by the argument). A generic `Traverse` is deferred until
 the compiler can infer `func(T) -> Result[U, E]` parameters.

 Go FFI stays for what MyGO cannot express: `defer`-based closing, nil checks on
 foreign pointers, `select` on cancellation, variadic forwarding, and library
 calls (`gorm`, `goldmark`, `bluemonday`, `rsa`, `json`, `time`, `strings`).
 Inline `go[...]` is narrowed to those cases; `MediaSafeName` and `MediaFileID`
 are the first two business-logic blocks to move into MyGO.

 ### 4. Routes become flat pipelines with typed steps

 Handlers keep their signatures (`w`, `request`, `parts`) but delegate to small
 helpers:

 - `WithActor(settings, db, site, w, request, fn func(auth.Identity) -> Result[(), Failure])`
 - `WithJSON(w, request, limit, target, fn func() -> Result[T, Failure])`
 - `Complete(w, result, render func(T) -> ())`

 This removes the repeated "decode, check `IsErr`, write 400, else continue"
 pyramid. The helper signature uses concrete `Result[(), Failure]` so it sidesteps
 the generic-result inference gap.

 ### 5. impl ownership follows package ownership; typeclasses need consumers

 Projections become static or instance methods on the type they build
 (`PostOutput.FromRecord`, `CommunityOutput.FromView`, `Failure.Status`), inside
 the defining package. Record-side helpers stay in `storage`. Typeclass impls are
 added only where generic code consumes them: `Ord[PostOutput]` for
 `Sorted`-style ordering, `ToString[Failure]` for diagnostics, `Default` for
 configuration groups, and a `Validatable` rule interface for configuration
 validation tables. Everything else stays an inherent `impl`.

 ### 6. Ordering uses stable sorts, never the in-place variants

 `SortedBy` copies and sorts stably, which matches the current `ThreadBefore`
 ordering and the selection sort it replaces. `Sort`/`SortBy` mutate the backing
 array and are avoided. A comparator equivalence test runs against the four
 ordering modes before the old selection sort is deleted.

 ### 7. Migration order and commit boundaries

 One module per commit, in dependency order: leaf packages (`content`, `config`,
 `auth`), then `storage`, then `federation`, then `server`, then `cmd/commune`.
 `profile-acct-lookup` is unimplemented; module work proceeds on packages it does
 not touch, and `profiles`/`federation` handle overlap last if that change lands
 first. Each commit carries its regenerated `zz_*.gen.go` files.

 ## Risks / Trade-offs

 - Public error text drift → the mapping table is test-driven against the current
   literal pairs, and the existing handler tests assert status codes and bodies.
 - Silent behavior change in a rewritten branch → every rewritten function keeps
   its call-site contract and the module test suite runs before the next module
   starts; ordering and policy logic get equivalence tests where the suite is
   thin.
 - Missing or guarded enum coverage → exhaustive switches are compiler-checked,
   guarded cases always carry an unguarded fallback, and every enum ships with
   parse/render tests.
 - Large generated diffs obscure review → module-sized commits plus `make verify`
   keep regeneration deterministic and reviewable.
 - Generic helper friction → helpers use concrete failure types and anchored
   element types until the compiler inference gap is fixed.
 - Typeclass ambiguity with multi-parameter instances → single-parameter
   instances are preferred; two-parameter instances (`From`) are avoided.
 - Overlap with the in-flight profile change → sequencing rule above, plus
   per-module reverts.


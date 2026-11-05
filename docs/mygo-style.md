# MyGO style in commune-backend

This repository uses MyGO features where they make the domain explicit. The
rules below are enforced by review, and each names a place in this tree that
shows the pattern (or the problem it replaces).

## 1. Patterns are unqualified, constructors are qualified

`switch` cases match on the variant name alone:

```mygo
switch policy
  case Open => "open"
  case Members => "members"
end
```

Constructing a value in expression position uses the type-qualified form:
`Policy.Open`, `Failure.Invalid("actor")`. Writing `case Policy.Open` is
accepted by the compiler today but degrades to an always-true branch, so it is
never allowed; a case body like `case Some(v) => ...` in
`internal/content/rich.mygo` is the reference shape.

## 2. Enum switches are exhaustive, and guards need a fallback

The compiler rejects a switch that misses a variant
(`non-exhaustive switch: missing variant(s) ...`). A guarded case does not count
as coverage, because the guard may be false, so every guarded switch also needs
an unguarded branch:

```mygo
switch (parts.Len(), parts.Get(2).UnwrapOr(""))
  case (3, "communities") => CommunityRoute(...)
  case (4, "posts") => PostRoute(...)
  case (_, _) if parts.Len() >= 5 => ContextBackfillRoute(...)
  case _ => WriteErrorJSON(w, 404, "not found")
end
```

`internal/federation/signature.mygo` already uses this shape for parsed keys.

## 3. Prefer prelude combinators over accumulator loops

Collection work goes through `Map`, `Filter`, `Fold`, `Find`, `Any`, `All`,
`Partition`, `ZipWith`, `SortedBy`, `Distinct`, `Take`/`Skip`, and
`Map.FromPairs`/`Keys`/`Values`. `Sorted`/`SortedBy` copy before ordering;
`Sort`/`SortBy` mutate the receiver, so the copy variants are the default.

Replace:

```mygo
var enabled = false
input.Sites.Each(func(site: Site) -> ()
  if site.RegistrationEnabled then enabled = true end
end)
```

with `input.Sites.Any(func(site: Site) -> Bool site.RegistrationEnabled end)`.
`internal/config/participation.mygo` still holds the accumulator form and
`internal/server/browser_output.mygo` holds a hand-written selection sort plus
`Filter(...).Get(0)` lookups; both are migration targets.

When a `Slice[Result[A, E]]` must become `Result[Slice[A], E]`, use
`functional.Sequence`. A fully generic `Traverse` is not writable with the
current compiler (a `func(T) -> Result[U, E]` parameter with generic `U` fails
unification), so helpers take anchored or concrete types.

## 4. Model domain values as enums; convert at the boundary

Enums lower to a Go interface plus variant structs, so they cannot be JSON or
GORM field types. Records and wire structs keep `String` fields; each boundary
gets a total parse and render pair, and the domain code only sees the ADT.
`internal/auth/community_policy.mygo` currently compares raw strings in
`Valid`/`CanRead`/`CanPost`; after migration those become exhaustive switches
over `FederationMode`, `ReadPolicy`, and `PostPolicy`.

## 5. Failures are typed; rendering happens once

Repositories and federation code return `Result[T, Failure]`. HTTP status and
public message are derived from one exhaustive mapping
(`Failure.Status()` and `Failure.Render()`), replacing the string ladder in
`FailStatus` (`internal/server/forum.mygo`). Unknown internal reasons still map
to `503` with the original text so no caller loses information.

Handlers do not build error responses by hand; they pass the failure to
`Fail`, which renders it.

## 6. impl ownership follows package ownership

`impl` blocks only attach methods to types declared in the same package; a
cross-package impl is accepted by MyGO and silently dropped from generated Go.
Projections therefore live beside their DTO (`PostOutput.FromRecord` in
`internal/server`), and record-side helpers stay in `internal/storage`.

## 7. Typeclasses need a generic consumer

Use an interface impl when generic code consumes it, not for decoration:

- `Ord[PostOutput]` so `Sorted` can order without a hand-written comparator.
- `ToString[Failure]` for diagnostics that format any failure.
- `Default` for configuration groups reconstructed from zero values.
- A validation interface for rule tables (`Validatable`).

Everything else stays an inherent `impl`. Typeclass methods are invoked with
receiver syntax (`failure.Status()`); they are not free functions, and
multi-parameter instances are avoided because dispatch can be ambiguous.

## 8. Inline Go is a boundary, not a tool for business logic

Keep `go[...]` for what MyGO cannot express:

- `defer {file}.Close()` style cleanup (`internal/storage/media_files.mygo`).
- nil comparisons on foreign pointers (`internal/storage/gorm.mygo`,
  `internal/federation/signature.mygo`).
- `select` on cancellation and timers.
- variadic forwarding and library calls that take `...`.
- assigning function values into foreign struct fields or building foreign
  option structs.

Business logic moves back into MyGO. `MediaSafeName` and `MediaFileID` in
`internal/storage/media_files.mygo` are the reference offenders: character
sanitization and charset validation are `String`/`Slice` work with prelude
combinators.

## 9. Statement-level details worth remembering

- `case ... then` block bodies close with their own `end`; arrow bodies do not.
- All branches of a `switch` or `if` expression share one type; `fmt.Println`
  returns `(int, error)`, so wrap it as `let _ = ...` inside a `()` branch.
- `if` stays appropriate for a single early guard or a two-way value choice;
  three or more mutually exclusive branches become a `switch`.
- Prefer immutable `let` plus masking over `var`; reserve `var` for Go FFI
  targets (`Ref` writes, `json.Unmarshal` destinations) and lease/retry state.


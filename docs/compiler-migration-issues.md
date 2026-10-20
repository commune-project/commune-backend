# MyGO test migration findings

Verified on 2026-10-14 with compiler source commit
`77319e6bc3c7ed95087011bf3ebd6e9243255840`, using the default bootstrap
compiler built by `make compiler`.

## Early return loses the Result success type (resolved)

Reverified on 2026-10-14 with compiler commit
`ec912b1849a3b5be95f254376bb29e0f8518ee2f`. The minimal reproduction below
now generates `Err[struct{}, string]`, and its original isolated assertion
passes. Explicit generic arguments on early Err returns have been removed
from the application. `internal/storage/compiler_test.mygo` retains a MyGO
regression check for `IsErr()` and pattern matching.

Minimal input:

```mygo
package probe

func Guard(fail: Bool) -> Result[(), String]
  if fail then
    return Err("failure")
  end
  Ok(())
end
```

At the original compiler revision, generation succeeded but returned:

```go
return Err[any, string]("failure")
```

The expected instantiation is `Err[struct{}, string]`. The generated function
can compile because the Result interface permits this value, but matching
`Result__Err[struct{}, string]` fails. Consequently `IsErr()` can return false
for a real error. An isolated Go assertion on `Guard(true)` reproduced:

```text
wrong error type: prelude.Result__Err[interface {},string]{F0:"failure"}
```

Previous workaround: write `return Err[(), String](...)` explicitly. The
migration-history tests now check both `IsOk()` and `IsErr()` so malformed
Result variants cannot pass merely because they are not Ok.

Related previously observed case: an early `return Ok(None)` in
`Result[Option[AccountRecord], String]` loses the Option element type.
The repository uses a typed `Option[AccountRecord]` binding and an explicit
Ok instantiation. This related case was not independently reproduced during
this migration.

## Implementing Go interfaces with MyGO types

Minimal input:

```mygo
package probe

import io "go:io"

struct Resource
  Name: String
end

impl Resource
  func Close(self: Resource) -> Result[(), error]
    Ok(())
  end
end

func AsCloser(resource: Resource) -> io.Closer
  resource as io.Closer
end
```

Generation succeeds. Go compilation fails:

```text
cannot convert resource (variable of struct type Resource) to type io.Closer:
Resource does not implement io.Closer (missing method Close)
```

This follows the documented lowering of inherent methods to renamed
top-level functions. It is an interoperability capability gap, rather than
a violation of that documented lowering. Supporting this use case requires
Go receiver methods or generated interface adapters, including conversion
from MyGO Result returns to Go's error and multiple-return conventions.

Current boundary: the handwritten SQL drivers have been replaced by sqlmock.
`internal/testtransport` only bridges fixture construction, GORM connection
setup and panic/recover. Test scenarios and assertions are MyGO. The remaining
production Go file embeds SQL migration resources. SQLite repository tests
and isolated real PostgreSQL tests now complement SQL expectation tests.

## Cross-package Go field methods need an explicit import

Verified on compiler commit `ec912b1849a3b5be95f254376bb29e0f8518ee2f`:

```mygo
package probe

import httptest "go:net/http/httptest"

func RecorderBody() -> String
  let recorder = httptest.NewRecorder()
  recorder.Body.String()
end
```

Default bootstrap inference fails:

```text
unknown field by.Buffer.String
```

Adding `import bytes "go:bytes"` allows the application health test to
generate and compile. The probe does not name a bytes type in source; the
compiler should resolve the exported Body field's package/type itself.
The reported `by` name is the alias used by the Go httptest source.
An isolated reproduction is in `/tmp/commune-ffi-alias-probe`.
The application currently uses the explicit import workaround.

## Transitive MyGO return types lose package qualification (resolved)

Verified with compiler commit `ec912b1849a3b5be95f254376bb29e0f8518ee2f`.
In `internal/server/authentication_test.mygo`, importing storage and calling
`AccountRepository.Create(...).Unwrap()` without importing auth generates:

```go
MygoIN6ResultM6Unwrap[Identity, string](storage.MygoIN17AccountRepositoryM6Create(...))
```

The return type is `auth.Identity`, defined in a third package, rather than a
server-local type. MyGO generation succeeds, but Go compilation fails with
`undefined: Identity`. The compiler should retain the defining package on the
return type and add its import when emitting inferred generic arguments.

Reverified with compiler commit `44ad240c36d845af54c04184d471f9e53eceeae9`:
the HTTP tests now generate `auth.Identity` and automatically import auth
without a source import or result annotation. The application workaround has
been removed, including the CLI account-creation result annotation.
The Go field-method issue above remains: removing bytes from all files in the
server package still fails with `unknown field by.Buffer.String`. An explicit
bytes import in another source file can mask that issue for the whole package.

## Inferred numeric bindings lose their Go width (resolved)

Originally verified with compiler commit `44ad240c36d845af54c04184d471f9e53eceeae9`.
`internal/storage/site_policy.mygo` initially contained:

```mygo
let count = 0i64
let result = query.Count(Ref.new(count))
```

Generation succeeds but emits `count := 0`, which Go infers as int. The GORM
call fails compilation with:

```text
cannot use &count (value of type *int) as *int64 value in argument to query.Count
```

Explicitly declaring `let count: Int64 = 0i64` emitted the required int64 binding.
Reverified with compiler commit `6cbefeecb8cb9fd75518b320051b7b54fdb5b69a`:
`let count = 0i64` now generates `count := int64(0)`. The application
annotation has been removed.

## Nested channel Result unwrapping loses generated calls (resolved)

Observed while adding `posts_test.mygo`; the compiler checkout HEAD at the end
of verification was `e8442b045c75b637970c70995f55950b6957f8d8`.

```mygo
let results = concurrency.MakeChan[Result[PostRecord, String]](2)
let post = results.Receive().Unwrap().Unwrap()
```

Generation succeeded but emitted only the Option unwrap, without generic
arguments or the nested Result unwrap:

```go
post := MygoIN6OptionM6Unwrap(concurrency.MygoIT13IReadableChanFN4ChanGN1TEGN4ChanGN1TEN1TEM7Receive(results))
```

Go compilation reported `cannot infer A` at that call. The expected output
must receive `Option[Result[PostRecord, String]]`, unwrap the Option with an
explicit Result element type, then unwrap the Result to PostRecord.

Reverified with compiler commit `6cbefeecb8cb9fd75518b320051b7b54fdb5b69a`:
the chain now generates both unwraps with explicit generics, so the test uses
the direct form again:

```mygo
let post = results.Receive().Unwrap().Unwrap()
```

The generated calls now carry the required type arguments and the isolated
PostgreSQL suite passes without the intermediate bindings.

## Go interface cast attached to a struct literal (open)

A further expression inference issue was observed while adding the community
repository: `query.Clauses(clause.Locking{Strength: "UPDATE"} as
clause.Expression)` is rejected as `cannot unify Locking with Expression`.
Binding the Locking value first, casting the binding to clause.Expression, then
passing it to Clauses compiles and passes the PostgreSQL transaction tests.
Reverified as still failing with compiler commit
`6cbefeecb8cb9fd75518b320051b7b54fdb5b69a`. The application keeps the
stepwise workaround; the compiler checkout was not changed.

## An import alias shadows a same-named local variable package-wide (resolved)

Originally observed with compiler commit `6cbefeecb8cb9fd75518b320051b7b54fdb5b69a`.
Adding `import hash "go:hash"` to `internal/storage/receipts.mygo` broke
`internal/storage/accounts.mygo`, which uses a local variable named `hash`:

```text
internal/storage/accounts.mygo:53:8: unknown Go package member IsErr
```

The line is `if hash.IsErr() || uri.IsErr() then`; the compiler resolved the
local `hash` to the new package import instead of the local binding. The import
alias and an unrelated local variable of the same name in another file of the
package should not collide. Fixed in the compiler; `receipts.mygo` now uses
`import hash "go:hash"` directly and regenerates cleanly.

## Negative duration literals

`now.Add(-2 * time.Hour)` reports `arithmetic operator * type mismatch: cannot
unify Int with go:time.Duration`, and `now.Add(-2 as time.Duration * time.Hour)`
reports `unary - requires a numeric operand`. The working form is
`now.Add((0 - 2) as time.Duration * time.Hour)`. The compiler checkout was not
changed; this only affects negative duration expressions.

## Verification commands

## Composite-literal method calls in conditions and bindings

Observed with compiler commit `6cbefeecb8cb9fd75518b320051b7b54fdb5b69a`.
Calling a method directly on a struct literal breaks two ways:

```mygo
# parse error: if CST lacks its condition expression
if FeedRepository{DB: db, SiteID: "b"}.ReadObject(ctx, id, viewer, false).IsErr() then
  ...
end

# inference error: unknown field PostRepository.ID
let received = PostRepository{DB: db, SiteID: "b"}.Receive(ctx, incoming, author).Unwrap()
```

Both work once the receiver is bound to a named variable first:

```mygo
let receiver = PostRepository{DB: db, SiteID: "b"}
let received = receiver.Receive(ctx, incoming, author).Unwrap()
if receiver.ReadObject(ctx, id, viewer, false).IsErr() then
```

The application now binds every repository receiver before calling it; the
compiler checkout was not modified.

## Verification commands

## Inline Go policy

Application code is written in MyGO. Inline Go is limited to expressions MyGO
cannot yet represent, currently: nil comparisons (`block == nil`,
`query.Error != nil`, `parsed.User != nil`), the RSA public-key type assertion,
the redirect callback returning Go's `error`, and `defer` statements. Each is a
single bound expression; no formatting, reflection, or extra call is used to
imitate a missing feature.

All handwritten application test files are now `*_test.mygo`; generated
`zz_*.gen_test.go` files are compiler output. Run `make test` to generate and
execute them. Interface and Result reproductions were run in an isolated
`/tmp/commune-interface-probe` module, outside the application test packages.

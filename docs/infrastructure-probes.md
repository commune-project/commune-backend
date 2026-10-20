# Infrastructure FFI evidence

Verified on 2026-10-12 with MyGO commit
`77319e6bc3c7ed95087011bf3ebd6e9243255840` and Go 1.27.1.
Run `make test` to regenerate from MyGO and execute the Go test harness.

Application probe behavior is in `internal/infrastructure/probe.mygo`.
`probe_test.mygo` provides assertions and HTTP request/response fixtures.
SQL failure injection uses sqlmock v1.5.2; the former handwritten fake driver
has been removed.

| Boundary | Executed evidence | Adaptation |
| --- | --- | --- |
| HTTP | ServeMux invokes a generated handler; status, content type and JSON DTO are checked | Inline Go converts the MyGO function to `http.HandlerFunc` |
| JSON | DTO serialization, nested RawMessage serialization, unknown extension retention and malformed JSON rejection | No adapter; retain original input separately because encoding/json compacts RawMessage |
| SQL | database/sql scans through a reference, commits success, rolls back scan failure, and propagates begin/commit errors | Inline Go dereferences the scan destination for the returned value |
| Crypto | RSA-2048 key creation, SHA-256 hashing, PKCS#1 v1.5 signing/verification and changed-body rejection | Inline Go slices the fixed-size digest array |

`Ref.new` must receive an addressable local variable, rather than a string
literal, for the SQL scan destination. The SHA-256 Go import now generates
successfully with this compiler revision.

These tests verify generated FFI behavior. The injected SQL driver is not a
PostgreSQL server. HTTP tests execute callbacks in-process and are not live
federation evidence. Exact payload retention is distinct from JSON
reserialization and does not yet establish duplicate-key rejection or nested
ActivityPub authority verification. Those requirements remain in later tasks.

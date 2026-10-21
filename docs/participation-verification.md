# Participation implementation verification

Date: 2026-10-21. Change: `add-forum-participation-and-media`.

## Reproducible checks

```sh
ulimit -v 8000000
export GOCACHE=/tmp/commune-participation-gocache
export GOMODCACHE=/tmp/commune-mygo-modcache
timeout 420 make build test test-postgres
openspec validate add-forum-participation-and-media --strict
git diff --check
```

All checks above passed on 2026-10-21. The final PostgreSQL run passed every
package; server tests took 12.125 seconds and storage tests 13.209 seconds.
The focused query-plan run also passed all four selected tests. Temporary logs
were `/tmp/commune-final-checks.log` and `/tmp/commune-query-checks.log`; the
commands and committed test sources, rather than temporary logs, are the
reproducible evidence.

The Makefile regenerates Go in dependency order before building. Generated Go
was produced by MyGO, not edited manually. The PostgreSQL script creates an
isolated real database and runs all packages with caching disabled. It requires
local PostgreSQL tools and permission to create sockets/listen on loopback.

## Task evidence map

| Tasks | Implementation and executable evidence |
| --- | --- |
| 1.1–1.4 | Configuration validation; migrations 006–012; `TestPostgresRegistrationMigrationUpgrade`, registration conflict/concurrent redemption tests, media binding and notification occurrence tests. |
| 2.1–2.4 | `registration_test.mygo` in storage/server; final-password, resend/site isolation, expiry, duplicate/rate races, provisioned login, strict HTTP guards; verification encryption/mail retry tests and fake SMTP tests. No real recipients are contacted. |
| 3.1–3.5 | `media_files_test.mygo`, `media_test.mygo`, and server media HTTP tests: root confinement, symlinks, quotas, malformed images, bindings, private reads, safe download and cleanup. |
| 4.1–4.5 | `internal/content/README.md` pins dependencies and APIs; content rich/mention/post tests; `TestPostgresRichPostAtomicityAndMentions`, `TestPostgresRichBrowserAndDiscoveryBudget`, `TestPostgresRichMutationOutboxAtomicity`. |
| 5.1–5.2 | Profile owner HTTP tests, Person serialization and authoritative update tests in `internal/federation/profiles_postgres_test.mygo`; immutable identity, stale/forged updates and direct remote avatar URLs. |
| 6.1–6.3 | Rich object parser/representation tests, `TestPostgresRichActivityReception`, `TestPostgresFederationMediaActorAuthorization`, private HTTP/public no-proxy test. Explicit restricted audiences cannot enter publicly readable communities; legacy audience omission retains verified community delivery semantics. |
| 6.4–6.6 | `TestPrivateMediaSignedFetchBounds`, private-cache expiry/revocation and HTTP ACL tests; generation leases, previews, expiry without renewal, metadata retention, and signed fetch bounds. Migration 012 invalidates cached generations on received-resource policy/reception changes. |
| 7.1–7.3 | Notification occurrence/privacy, remote/revocation, concurrent projection/snapshot, HTTP routes, and remote reaction replay tests; committed outbox publication rollback tests. |
| 8.1–8.3 | Search validation/storage/HTTP tests and notification plan test; exact current plan and page-size counts in `forum-search-verification.md`. |
| 9.1–9.2 | Worker cancellation test; mail lease/final-attempt tests; cache cleanup tests; API/configuration/authentication docs with JSON, multipart, Markdown, SMTP, backup and rollback examples. |
| 9.3–9.4 | Real multi-site HTTP and independent-process exchange in `scripts/participation-acceptance.py`; versioned results in `participation-acceptance-2026-10-21.md`. |
| 9.6–9.7 | Full Makefile regeneration/build/unit/PostgreSQL checks and strict OpenSpec validation, plus this evidence map. |

## Acceptance boundary

The real PostgreSQL suite is supplemented by the completed end-to-end multi-site
matrix (9.3) and two independent Commune process exchange (9.4). See
[versioned commands, results and bootstrap boundaries](participation-acceptance-2026-10-21.md).

Lemmy/Mastodon/Misskey live acceptance (9.5) is deferred by the user's explicit
instruction. No tested peer versions or live interoperability result is claimed.
Local fixtures and controlled signed HTTP origin tests establish only their
documented code paths. No sync, archive or commit is performed by these checks.

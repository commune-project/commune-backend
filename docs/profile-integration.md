Profile participation integration (tasks 5.1–5.2)
==============================================

Migration `internal/migrationfiles/migrations/008_profiles_content.sql` is owned
by the profile implementation. Main must register it in the migration catalog.
It adds `profiles` (Person Actor URI primary key) and posts `content_format`
(`legacy` default) / `search_text` (empty default, markup-stripped backfill).
Main owns post_mentions separately. Migration 007 remains owned by media.

Main must call `server.ProfileRoute(settings, db, site, w, request, parts)`
before ordinary API dispatch. The route calls BindProfileAvatar using the
media agent's MediaRepository.BindAvatarTx and converts its relative binding URL
to the absolute current-site URL required by ActivityPub. No filesystem is opened
for this metadata transaction. No server.mygo changes are made here.
`ProfilesRoute` is a compatible forwarding alias with the same six arguments,
so the existing ParticipationRoute integration is supported.
The route handles public GET /api/v1/profiles/{username} and authenticated
GET/PATCH /api/v1/profile with strict JSON, configured lengths, origin and CSRF.

The internal media helper is BindProfileAvatar(ctx, tx, site, settings, identity,
uploadID) -> Result[AvatarBinding,String]. Both binding and profile changes use
the supplied transaction. Empty uploadID means removal (JSON
null or empty string); omission preserves the existing avatar. Validate current
site/owner, purpose=avatar, decoded raster image and unused upload. Revoke the old
binding and return {ID, URL}, where URL is the explicit public resource binding
URL. Removal returns empty fields. Reject foreign/reused uploads; never fabricate
a URL or accept a client-supplied avatar URL. Media reads must check profiles'
current avatar_binding_id; replacement/removal must deny the previous binding.
The route maps binding validation/conflict errors to 400/409.

Local profile save and federation.QueueProfileUpdate run in that same transaction.
The update is stored durably and delivery targets accepted, non-blocked Person
followers. Person discovery now enriches the existing Actor representation.
Verified inbox Person Updates use unchanged actor identity, remote-only Person,
site block checks and increasing object.updated timestamps. Public avatar URLs
are HTTPS metadata only; this implementation makes no avatar GET/HEAD or cache job.

Rendering dependency: content.RenderRich(source, "markdown") and
content.SanitizeRichHTML(remoteHTML) supplied by the rich-content implementation.
No biography mention-resolution or notification call is made.

Verification (2026-10-20)
-------------------------

All compiler/test invocations use `ulimit -v 4194304`, `timeout 60s` (server sync
allows 90s),
`GOCACHE=/tmp/commune-profile-gocache`, and the existing
`GOMODCACHE=/tmp/commune-mygo-modcache`.

Passed: compiler `sync internal/federation` and Go focused tests
`TestPersonProfileSerialization`, `TestPersonUpdateAuthorityAndFreshness`,
`TestPostgresPersonUpdateFreshnessBlocksAndLocalAuthority`. The last test ran
against a temporary isolated PostgreSQL cluster, not a mock or skipped fixture.

Passed: direct PostgreSQL upgrade from migrations 001–005 with a legacy HTML post
to migration 008. Checked legacy format default, Chinese search text, removed
HTML/script payload, accepted Person profile and rejected Group profile FK.

Profile HTTP test source: internal/server/profiles_test.mygo,
`TestPostgresProfileOwnerHTTP`; this covers session/origin/CSRF, public output,
Markdown biography, durable Update, actual media binding replacement/removal,
foreign upload refusal, Person icon projection, immutable fields, field bounds,
and disabled accounts. PASSED against a temporary isolated PostgreSQL cluster
after successful compiler `sync internal/server` and `sync internal/federation`.

Final focused test command (all four tests executed and passed; none skipped):

    go test ./internal/federation ./internal/server -run 'Test(PersonProfileSerialization|PersonUpdateAuthorityAndFreshness|PostgresPersonUpdateFreshnessBlocksAndLocalAuthority|PostgresProfileOwnerHTTP)$' -count=1 -v

No claim of live external-peer interoperability is made. Remote Person Updates
require a nonzero object.updated timestamp and ignore versions no newer than
the stored timestamp. Public avatars remain external HTTPS URL metadata.

Two small shared-package generation fixes were necessary: participation worker
negative durations now negate the integer before casting to time.Duration, and
SMTP TLS MinVersion constants explicitly cast to UInt16. Generated Go was
produced only by the compiler. No commits, task checkboxes, server.mygo edits,
or migration catalog edits were performed by this implementation.

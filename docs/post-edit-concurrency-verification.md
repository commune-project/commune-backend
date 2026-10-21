# Post edit concurrency verification

## Writer inventory

| Writer | Transaction and revision behavior |
| --- | --- |
| PostRepository.Publish | Content, local bindings and mentions share its transaction; new row starts at 1 through the mapped database default. |
| Edit / EditContent / EditResolvedContent | Required caller revision; MutateAuthor locks the post and checks site/authorship before comparison; text, revision, bindings, mentions and notification changes share the transaction. |
| PostMutation PATCH | Outer transaction includes repository save and QueuePostMutation; an outbox error rolls back the nested savepoint and revision. |
| PostRepository.Delete | Locked transaction deactivates bindings/mentions and advances revision on the first tombstone only. |
| PostRepository.Receive | Canonical row lock; new row starts at 1, accepted newer content increments once, stale/duplicate/tombstone replays do not. |
| ReceiveRichActivity / ApplyRichMutation | Outer transaction includes Receive and media/mention reconciliation or deletion invalidation; remote wire revisions are not trusted. |
| Reactions, replies, site hide, community inclusion | No modification of the parent's editable content revision. |

Source reads use a repeatable-read transaction so body, format, attachments and version share one snapshot. Version is global to the shared post, including colocated sites.

## Acceptance evidence

On 2026-10-21 generation, Go build, ordinary tests, and the complete isolated
PostgreSQL suite passed after restoring the correct compiler branch. The
compiler was not modified by this change. Reproduce with local listening
permissions for the HTTP/SMTP fixtures and temporary PostgreSQL cluster:

```sh
ulimit -v 8388608
export GOCACHE=/tmp/commune-version-gocache
export GOMODCACHE=/tmp/commune-mygo-modcache
export GOMAXPROCS=2
timeout 720 make build test test-postgres
```

The full Makefile generation and build completed first. After correcting a
test-local variable name and distinguishing creator management access (403)
from ordinary revoked membership (404), the server package was regenerated
with the same compiler. Final checks reused those generated outputs:

```sh
timeout 240 /tmp/commune-mygo-build/mygo sync internal/server
timeout 300 make -o generate build test test-postgres
openspec validate add-post-edit-concurrency-control --strict
git diff --check
```

All final commands passed. PostgreSQL tests run with caching disabled; server
tests took 17.858 seconds and storage tests 19.310 seconds. The temporary final
log is `/tmp/commune-version-final.log`. The initial sandbox-only network
failures were resolved by running the same checks with local listening access.

Generated code was produced by MyGO. Added acceptance sources include
`TestPostgresConditionalAuthorEdits`, `TestPostgresPostVersionMigration`, and
expanded shared-post, rich-content and outbox tests. They cover sequential and
concurrent saves, source versions, malformed preconditions, access/CSRF/deletion
precedence, attachment/mention preservation, queue rollback, overflow,
unchanged saves, inbound revisions, and interaction independence. All executed
successfully in the final PostgreSQL run.

| Contract area | Executable evidence |
| --- | --- |
| Source snapshot, mandatory integer precondition, success version, sequential and simultaneous drafts | TestPostgresConditionalAuthorEdits |
| CSRF, hidden/deleted content, non-author access, creator versus ordinary member revocation | TestPostgresConditionalAuthorEdits |
| Unchanged save, revision overflow rollback, likes/replies do not invalidate drafts | TestPostgresConditionalAuthorEdits |
| Existing-row migration preserves body/timestamps; positive-version constraint | TestPostgresPostVersionMigration |
| Accepted inbound updates and deletion advance; older updates and tombstone replays do not | TestPostgresSharedPostIdentity |
| Stale attachment save and validation failure preserve body, version, bindings and mentions | TestPostgresRichPostAtomicityAndMentions |
| Failed outbox insertion rolls back version and content; stale save creates no extra activity | TestPostgresRichMutationOutboxAtomicity |

Live deployment and frontend integration are separate from local PostgreSQL
acceptance and have not been performed.

## Deployment and recovery

PATCH now requires a positive signed 64-bit JSON integer expected_version. Coordinate clients to retain source versions, preserve drafts on 409, and request fresh source for manual comparison. Do not automatically retry an old draft with a newly fetched version. Clients must preserve integer values exactly.

Drain old writers before migration 013 and deploy revision-aware binaries together with compatible clients before reopening writes. Mixed old/new writers are unsupported. For rollback, pause author writes and retain the additive column and its values; prefer a forward fix. Never reset revisions or promise concurrency protection while unconditional old writers are active.

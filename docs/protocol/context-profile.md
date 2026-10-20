# Commune discussion context profile

This document separates the requirements inherited from FEP-7888 from the
direct-collection convention Commune adds for its federated forum discussions.
It is an implementation profile, not a claim that FEP-7888 requires this exact
collection layout.

## Upstream FEP-7888 behavior

The preserved FEP-7888 snapshot states that an object may use the ActivityStreams
`context` property to identify a discussion grouping. The property can be absent,
and an interaction may copy, replace, or omit a parent's context. The snapshot is
pinned at `snapshots/fep-7888.md`; its digest and retrieval date are recorded in
`snapshots/SHA256SUMS` and `baseline.md`.

The upstream text distinguishes `context` from JSON-LD `@context` and from
`audience`. It also describes a possible canonical collection for context
contents and recommends keeping a context authority in the loop when copying its
context. Commune does not treat those recommendations as permission grants: a
context claim, a successful document fetch, or an audience value cannot by
itself establish inclusion or read access.

The executable parsing evidence is
[`internal/federation/context_refs_test.mygo`](../../internal/federation/context_refs_test.mygo).
It covers absent, string, collection, object, link and multiple mixed references,
along with repeated `context` properties and the separation from `@context` and
`audience`.

## Commune direct-collection convention

For a local federated discussion, Commune creates a stable context URI at
`{canonical-origin}/contexts/{id}`. A GET of that URI returns an
`OrderedCollection` with an `id`, `totalItems`, and `first` page link. Page links
are query URLs on the same context URI. The collection document's
`attributedTo` identifies the hosting Group actor.

Commune treats that context URI as the discussion identity and its advertised
collection as the authority's membership evidence. A `Collection` or
`OrderedCollectionPage` can be traversed through `first` and `next`; collection
entries may be URI strings, objects with `id`, or Links with `href`. Commune
fetches each canonical item before import and requires the fetched body's `id`
to match the requested URI.

This is a Commune choice. The protocol does not require every `context` value to
resolve to a collection, and other applications may use object, link, or peer
specific context forms. Commune retains those forms as declarations and does not
guess a collection relationship.

Communication includes the context URI on locally authored objects and uses the
resolved document's `attributedTo` (falling back to `actor`) when deciding which
context authority should receive an eligible interaction. Context authorities
are deduplicated against community followers before delivery.

Local-only discussions have internal identities only. They have no context URI,
ActivityStreams representation, remote resolution, delivery, or backfill.

## Declaration, acceptance, and navigation

`post_contexts` records a declaration from an object. `collection_memberships`
records the separately verified state and provenance. A local authority can
accept a local attachment; a signed or canonical collection action can verify a
remote relationship. A forged declaration remains outside the accepted
collection. Authoritative removal changes the membership state and stops new
collection presentation without deleting the shared post.

When a peer omits `context`, Commune can still follow its direct `inReplyTo`
ancestry to derive a local navigation root. Backfill can record accepted
canonical-collection membership for such an object, but it does not create a
`post_contexts` declaration. The inference therefore remains local and is never
advertised as the remote author's context claim.

Executable evidence:

- [`internal/storage/context_reply_test.mygo`](../../internal/storage/context_reply_test.mygo)
  covers independent parent/context storage and claim-versus-acceptance state.
- [`internal/storage/context_inclusion_test.mygo`](../../internal/storage/context_inclusion_test.mygo)
  covers accepted versus pending membership and authoritative removal.
- [`internal/federation/collection_traversal_test.mygo`](../../internal/federation/collection_traversal_test.mygo)
  covers mixed collection items, pagination links and deduplication.
- [`internal/server/context_backfill_test.mygo`](../../internal/server/context_backfill_test.mygo)
  covers bounded import, context-less navigation, idempotency, site hides and
  author tombstones.
- [`internal/server/federation_context_test.mygo`](../../internal/server/federation_context_test.mygo)
  covers context collection identity, paging, local-only exclusion and protected
  member reads.

## Evidence rules

An interoperability result may be labeled live only when it was observed against
the pinned peer release in an isolated deployment. Fixture and unit tests must be
labeled as executable protocol evidence, not live compatibility. Every report
records the tested release or commit, the source snapshot digest and date, the
request/response identities, the applied access policy, and the observed result.

Negative evidence is required. A report must state when a peer omits context,
uses a non-collection context, cannot authenticate protected reads, cannot
consume a direct collection, or does not support cross-server management. A
timeout is not evidence of support, and an absent context is not a malformed
object.

Direct collection import is bounded and idempotent. Evidence must identify the
page and item limits, rejected items, duplicate identities, and whether local
hiding or an author tombstone remained effective after a repeated pass. Protected
backfill evidence must identify the current member or manager authorization used
for each read and must show that non-members and revoked members receive no
collection, count, membership, or object disclosure.

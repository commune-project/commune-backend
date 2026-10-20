# Forum storage boundaries

`PostRepository.Receive` inserts a federated normalized object by canonical URI
inside a transaction. Conflicting concurrent imports lock and load the same
stored row, retaining one ID and current body. Each resolved SiteID receives
its own `site_posts` row. Identical bodies with different URIs remain separate.

The caller supplies verified author authority. This is an internal persistence
boundary, not an inbox or public import endpoint: HTTP signatures, nested
authority proofs, remote fetching and dispatch are still pending. Passing a
claimed URI from client JSON as authenticatedAuthorURI would be incorrect.
Neither post existence nor a reception row establishes viewing entitlement or
Group/context approval. Future APIs must enforce reception, current community
access and inclusion separately.

Existing author, community, object type, parent and original authored timestamp
must match. URI reuse by another actor fails. Newer authoritative versions update
the existing row; older versions leave it unchanged. Equal timestamps with
conflicting title/body/deletion state fail. Times are normalized to PostgreSQL's
microsecond precision before comparison. Author tombstones remain empty and
cannot be resurrected by either old Create replay or a later version. Reception
failure rolls back the inserted object and any update in the same transaction.

`CommunityRepository.Create` validates an enabled owning-site account, current
site origin, name and one of the three policy combinations. It records the
creator, approved initial membership and creation audit atomically. Federation
participation is fixed by the existing database identity guard. Federated
creation allocates a site-owned Group identity; local-only creation has no
Group URI or actor. Neither creation path schedules deliveries. Key provisioning,
community HTTP APIs and topic/reply publication are still pending.

`make test-postgres` runs actual concurrent receptions using MyGO Spawn/channels
against an isolated database. It also verifies author/version conflicts,
tombstones, reception rollback, and creation for all six federation/read/post
combinations. These results do not claim live ActivityPub interoperability.

## Eligible publication

`PostRepository.Publish` publishes a titled topic or a nested reply into a hosted
community after loading the community under lock and checking current posting
access. Only local authenticated accounts publish here; a service caller cannot
pass `remoteVerified` to bypass return to the local path. Topics carry a title
and become `Page`; replies omit the title and become `Note`, keeping their direct
parent. The parent must be a non-deleted post in the same community, so replies
cannot cross a community boundary. A topic without a title, an empty body, an
over-long field, or a non-member posting to a member-only community is rejected.

Local-only publication stores a random local identity with no canonical object
URI and records one owning-site reception. Federated publication mints the
site's canonical `objects/{id}` URI inside a transaction. Neither path creates
ActivityPub activities, audiences beyond the local community declaration, or
delivery jobs in this change, and none is created for local-only content. Group
announcement, outbox and delivery remain tasks 6.x. The receiving site, author
identity and parent ownership are stored explicitly, and community categories
are not involved.

`post_publish_test.mygo` verifies topic/reply/nested-reply identity, cross-community
parent rejection, cross-site and unverified-remote rejection, member-only posting
denial, local-only canonical-URI absence, and zero protocol activities or delivery
jobs. `community_creation_test.mygo` additionally asserts that a direct attempt
to convert a local-only community to federated is rejected by the identity guard.

## Author edits, deletion and reactions

`PostRepository.Edit` and `Delete` load the post under lock and require current
author authority: only the verified author of the post may change it, and the
edit must keep the topic/reply shape. Edits reject a tombstoned post, and the
database guard prevents resurrection, so an old Create can never restore a
deleted body. Deletion is idempotent.

`ReactionRepository.Like` and `Undo` require current read access; a reaction is a
read-adjacent interaction, so in an all-site-readers community a non-member may
react while only members may publish, and a members-only community denies both.
Reactions act only on the issuing actor's row: a duplicate like is idempotent,
re-like after undo restores it, and undo leaves other actors' reactions intact.
Local-only reactors must be owning-site accounts and carry no federation URI.

## Reads, counts, import and sharing

`FeedRepository` lists topics and replies, reads a single object and counts them,
always rechecking current access against the object's hosting community and only
ever returning objects this site received (and not hidden). Unauthorized callers
receive `not found`, so restricted metadata and counts do not leak. Community
metadata reads remain host-scoped; federation-policy reads resolve a community
without a host filter and grant no management authority to a non-hosting site.

`PostRepository.Import` records this site's reception only when the viewer may
currently read the object; the exact scenario "a shared ID another site stored
but this site has not received stays inaccessible" is verified. `ShareTo`
records an audience only between two unrestricted federated communities and is
rejected when either side is local-only or member-readable; `MoveTo` is always
rejected. These store-layer operations are the deliverable for the read/import
tasks; HTTP routing and the versioned API contract remain task 4.8.

## Moderation scopes

`FeedRepository.SetHidden` is site-scoped: it requires the resolving site's
current administrator or an explicit deployment superadministrator, touches only
that site's `site_posts.hidden_at`, is audited, and never mutates the shared
object. Hiding at site A therefore leaves site B's view and the object intact.

`CommunityRepository.RemovePost` is community-scoped and requires current
community management authority. It records `collection_memberships.state` as
`removed` (or `accepted` to restore) with the community's own actor as the
collection authority, so the exclusion applies to that community everywhere it
is shared while the object body, author tombstone state and other sites'
listings are untouched. `SetSubmission` records `pending`, `accepted` or
`rejected` declared-association state; community listings hide `removed` and
`rejected` entries so a rejected submission is never shown as accepted content.

`moderation_test.mygo` verifies non-administrator hiding rejection, A-hidden/B-
visible independence, unhide, community removal and restore, non-manager
rejection, community-wide scope, and rejected-submission exclusion. HTTP
endpoints for these operations remain task 4.8.
These operations are now also exercised end to end over HTTP by
`TestPostgresForumModerationHTTP` in `internal/server/forum_test.mygo`.

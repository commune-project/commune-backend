# Federation discovery (FEP transport, stage 5.1)

ActivityPub resources are served per resolved site, so every identifier uses the
owning site's canonical origin. `internal/federation` builds the representations
and `internal/server/federation.mygo` routes them.

| Method | Path | Media type | Success |
| --- | --- | --- | --- |
| GET | `/.well-known/webfinger?resource=acct:user@host` | `application/jrd+json` | 200 JRD |
| GET | `/users/{username}` | `application/activity+json` | 200 Person |
| GET | `/communities/{name}` | `application/activity+json` | 200 Group |
| GET | `/objects/{id}` | `application/activity+json` | 200 Page/Note/Tombstone |
| GET | `/activities/{id}` | `application/activity+json` | 200 stored payload |

Person and Group actors advertise `id`, `type`, `inbox`, `outbox`, a
`followers` collection, and a `publicKey` whose `owner` is the actor and whose
`publicKeyPem` matches the actor's stored key. WebFinger links `self` to the
same actor URI, and the requested host must equal the resolved site's authority,
so a site can never advertise another site's actor.

Key material is generated on first use by `EnsureLocalKey` (RSA 2048) and stored
per actor; only the public PEM appears in a representation. Key generation and
public-key derivation use the `crypto/rsa`, `crypto/x509` and `encoding/pem`
wrappers directly in MyGO rather than inline Go blocks.

Object retrieval serves only federated objects hosted by the resolved site whose
community is federated and openly readable; local-only, members-only, foreign
and unknown objects return a uniform `404`. A deleted object returns a
`Tombstone` with no body. Activities are served only for the site that owns the
stored activity URI, returning the retained original payload.

Content negotiation requires an ActivityPub `Accept` (`application/activity+json`
or an `application/ld+json` profile); other media types receive `404`. WebFinger
is independent of that check because it is a JRD document.

`TestPostgresFederationDiscovery` verifies WebFinger self-link and host scoping,
Person fields, inbox and public key, Group fields, local-only exclusion for both
Group and objects, members-only and cross-site object denial, tombstone
representation, retained activity payload retrieval, and rejection of a
non-ActivityPub `Accept`.

Collection endpoints are advertised in the actor but not yet served, and inbox
processing, signatures and delivery remain tasks 5.2 through 5.13.

## Request signatures (stage 5.3)

Actor keys are provisioned lazily by `EnsureLocalKey` (RSA 2048) and stored per
actor with only the public PEM exposed. `internal/federation/signature.mygo`
provides the primitives: `BodyDigest` (`sha-256=` base64 of the body),
`SignSignature`, `VerifySignature`, `ParseSignatureHeader`,
`RequestSigningString`, `FormatSignatureHeader`, `FreshDate` and
`KeyOwnedByActor`.

Requests use a `Signature` header with `keyId`, `algorithm="rsa-sha256"` and
`headers="(request-target) host date digest"`. `VerifyRequest` rejects a header
whose algorithm or covered-header list differs, a `Date` outside the configured
window, a signature that does not match the reconstructed signing string, or a
digest computed over a different body. `KeyOwnedByActor` requires the key
identifier to be the signing actor's own `#main-key`, so an instance key cannot
stand in for another actor.

`signature_test.mygo` verifies a signed request, and the rejection of a tampered
body digest, a different request target, a stale date, an unrelated key, and an
unsupported algorithm, plus key-ownership binding.

The remaining pieces are transport wiring: fetching a remote actor's key is
task 5.4 and enforcing signatures on shared-inbox requests is task 5.5. The two
Go fragments (`BlockMissing`, `AsRSAPublicKey`) exist only because MyGO has no
nil comparison or type-assertion syntax.

## Bounded remote retrieval (stage 5.4)

`internal/federation/fetch.mygo` resolves a remote identifier safely.
`BlockedIP` rejects loopback, private, link-local, multicast, unspecified and
non-IP values, which covers the cloud metadata address `169.254.169.254`.
`ValidateDestination` requires `https` (plain `http` only when the explicit test
switch is on), requires a host, and for a non-literal host resolves it and
rejects the request if any returned address is blocked, so a DNS name cannot
point at an internal service.

`Fetch` runs under a bounded context timeout and follows redirects manually: the
client's own redirect handling is disabled, each `Location` is resolved and then
re-validated through `ValidateDestination`, and the hop count is capped. A
response body is read through `io.LimitReader` at one byte over the limit so an
oversized body is rejected rather than truncated silently.

The limits come from the new `federation` configuration section:

```json
"federation": {
  "allow_private_network": false,
  "fetch_timeout_seconds": 10,
  "max_fetch_bytes": 1048576,
  "max_redirects": 5,
  "clock_skew_seconds": 300
}
```

`allow_private_network` is the explicit isolated-test switch; it defaults to
false and must stay false in production. `clock_skew_seconds` bounds signature
freshness for stage 5.3.

`fetch_test.mygo` verifies rejected loopback, metadata, plain-http and malformed
destinations, an accepted explicitly-configured local destination, a bounded
successful fetch, an oversized-body rejection, an in-range redirect, a redirect
loop stopped by the cap, and a strict-mode fetch refused without the test switch.

## Collections (stage 5.2)

Actor collections are served per resolved site with canonical identifiers:

| Method | Path | Representation |
| --- | --- | --- |
| GET | `/users/{username}/inbox` | empty `OrderedCollection` |
| GET | `/users/{username}/outbox` | `OrderedCollection` |
| GET | `/users/{username}/outbox?page=N` | `OrderedCollectionPage` of objects |
| GET | `/users/{username}/followers` | `OrderedCollection` (Person: 0) |
| GET | `/communities/{name}/inbox` | empty `OrderedCollection` |
| GET | `/communities/{name}/outbox` | `OrderedCollection` |
| GET | `/communities/{name}/outbox?page=N` | `OrderedCollectionPage` of objects |
| GET | `/communities/{name}/followers` | counted `OrderedCollection` |
| GET | `/communities/{name}/followers?page=N` | `OrderedCollectionPage` of actor URIs |
| GET | `/objects/{id}/replies` | `OrderedCollection` |
| GET | `/objects/{id}/replies?page=N` | `OrderedCollectionPage` of replies |

The collection document carries `id`, `totalItems` and a canonical `first` link
only when it has content; page links use `?page=N`. A page carries `partOf` (the
collection `id`), an `id` of the same canonical form, `next`/`prev` only when
those pages exist, and `orderedItems`. Page size is the configured maximum page
size, and an out-of-range page returns empty items with only the applicable
links.

Visibility is enforced before pagination and counting: an object appears only
when it is federated, hosted at the resolved site, and belongs to a federated
community with `eligible_users` read policy. Local-only objects, members-only
objects and objects hosted elsewhere are excluded, and a local-only community
exposes no collection at all. The inbox is always empty and advertises no page
link, so it never becomes a content index.

Outbox `orderedItems` currently contain object representations rather than
`Create` activities; activity-based outbox entries arrive with the federation
artifact work in stage 6.x.

`federation_collections_test.mygo` verifies collection types and totals, the
canonical `first`, page `id`/`partOf` and absent/`prev` links, empty
out-of-range pages, an empty inbox without a page link, reply pages carrying
their `Note` items, follower counts, and uniform not-found for a local-only
community and an unknown actor.

## Inbound receipt and dispatch (stage 5.5)

`POST /inbox`, `POST /users/{username}/inbox` and `POST /communities/{name}/inbox`
accept an activity. The request must carry `Signature`, `Date` and `Digest`
headers; the signer must be the activity's own actor, the key identifier must be
that actor's `#main-key`, the digest must cover the received body, and the date
must be within the configured clock-skew window. A missing or non-matching key
is rejected with `401` before any storage.

`storage.ReceiveActivity` runs in one transaction and stores the activity
identity and the original payload immutably. Reusing an activity URI with a
different actor, kind or payload is rejected as a conflict (`409`); an identical
replay is idempotent. Receipts are keyed by `(activity_uri, site_id,
recipient_actor_uri)` and are created only for local recipients resolved from
the activity's `to`/`cc`, so a duplicate delivered to site A leaves site B's
reception intact and a per-actor inbox additionally records its owner.

Accepted work is durable: rows start `pending`, `ClaimPendingReceipts` leases
them for processing with `FOR UPDATE SKIP LOCKED`, a live lease cannot be claimed
again, an elapsed lease can be reclaimed (as after a restart), and
`SettleReceipt` writes the terminal `accepted`/`rejected` state.

`federation_inbox_test.mygo` verifies a signed accept, an idempotent replay with
zero new receipts, independent reception at a second site without suppressing
the first, conflicting actor and payload reuse, stale `Date`, wrong signer and
missing signature rejection, lease exclusivity, lease expiry and reclaim, and
settled-state persistence.

Action-specific authorization (a valid forwarding signature does not authorize
a nested forged update) is task 5.6; delivery workers are task 5.7.

## Action authority and nested verification (stage 5.6)

`internal/federation/authority.mygo` parses an activity's `object`, which may be
an identifier string or an embedded object/activity. An outer signature
authorizes forwarding only:

- an embedded activity whose `actor` equals the forwarding actor's is trusted;
- an embedded activity from a different actor must be confirmed against its own
  canonical copy, fetched through the bounded client and matched on `id`,
  `actor` and `type`. An unreachable or mismatched copy is rejected as
  `unverifiable embedded author` before any storage;
- a `Create` whose embedded object would attribute authorship to another actor
  is rejected as `forged author`;
- an `Update` or `Delete` must name an object we already store, and the stored
  author must equal the signer, otherwise `unknown object` or `forged mutation`.

`federation_authority_test.mygo` verifies that a signed `Announce` relaying an
activity by an unrelated author is rejected while the same relay is accepted
once the author's canonical copy is reachable and matching, that an activity
embedded by its own signer needs no retrieval, that a signed `Update` of another
author's object is rejected, that the object owner's own update is accepted, and
that an update of an unknown object is rejected.

## Durable delivery (stage 5.7)

`internal/storage/broker.mygo` persists outbound work. `EnqueueDelivery` takes
the caller's transaction handle, so a mutation, its activity, its payload and
its jobs commit together and a rolled-back mutation schedules nothing.
`delivery_jobs` is unique on `(activity_uri, signing_actor_uri,
recipient_actor_uri, target_inbox)`, and the schema requires `lease_token` and
`lease_until` to be set together, so a lease is released by clearing both.

`ClaimDeliveryJobs` leases ready jobs with `FOR UPDATE SKIP LOCKED` and
increments `attempts`; a live lease cannot be claimed twice and an elapsed lease
can be reclaimed, which is what makes a crash mid-delivery recoverable. The
terminal transitions are `MarkDelivered`, `MarkDeliveryRetry` (backoff through
`available_at`), `MarkDeliveryFailed` (permanent, with `error_code`) and
`SuppressDelivery`.

`internal/delivery/worker.mygo` runs one batch. `Post` signs the request target,
host, date and body digest with the site actor's `#main-key` and sends it with
`Signature`, `Date` and `Digest` headers; the poster is a parameter so the lease,
retry and failure logic is exercised without a live peer. A job is retried with
backoff until `MaxAttempts`, then failed and reported.

`worker_test.mygo` verifies that a real signed POST is accepted by a peer that
independently checks the signature and digest, that a rolled-back transaction
schedules no job, that one unavailable peer does not block another job, that a
live lease is not double-claimed, that an expired lease is reclaimed, that a
recovered job completes, and that exhausted attempts end in a reported failure.

## Destinations and colocation (stage 5.8)

`storage.PlanDelivery` splits an activity's recipients by where they live. A
recipient whose actor belongs to a site in this deployment gets a local
`inbox_receipt` for that site instead of an outbound job, so colocated delivery
still flows through the receiving site's own inbox validation and policy rather
than bypassing it. Remote recipients are queued one job per (activity, signing
actor, recipient, inbox), which keeps each recipient's scope and terminal state
explicit.

`delivery.GroupJobs` then collapses jobs that name distinct recipients but the
same destination (activity, signer and shared inbox) into a single transmission;
the worker sends once and applies the result to every job in the group, so a
shared-inbox peer sees one POST while all its eligible local recipients still get
their own delivered/retried/failed state.

`destination_test.mygo` verifies that one remote shared inbox plus a distinct
remote inbox plus a colocated recipient plan as three jobs and one receipt, that
the colocated actor receives no outbound job, that the three jobs group into two
transmissions, that the poster is called twice, and that all three recipient rows
end delivered.

## Person following and boosts (stage 5.9)

Migration `004_person_follows.sql` adds `person_follows`, separate from the
community-scoped `follows` table: a follow of a person is not a community
subscription or a membership. A trigger requires the target to be a local
site-owned Person and the follower to be a Person. The standard library
checksum in `catalog.mygo` no longer needs an inline Go slice expression.

An inbound `Follow` naming a local Person records an accepted follower, then the
site issues an `Accept` whose `object` is the original Follow: the Accept is
stored as an immutable activity and payload and planned for delivery to the
follower's inbox in the same transaction. `Undo` of that Follow (matched through
the stored original activity and the same actor) marks the follower undone, and
the Person followers collection reflects the change immediately.

An ordinary `Announce` of a third-party object is recorded as a receipt only. It
creates no community membership and no group inclusion, which is what keeps boost
ingestion distinct from FEP-1b12 group approval.

`federation_follows_test.mygo` verifies that a signed Follow is accepted and
recorded, that an Accept is issued and queued to the follower, that the followers
collection counts and pages the follower, that the follow creates no community
membership, that its Undo removes the follower and empties the collection, and
that a boost produces a receipt with neither membership nor inclusion.

## Central local-only exclusion (stage 5.10)

`internal/storage/local_only.mygo` holds the exclusion predicates every
federation boundary consults instead of trusting an incoming identifier or a
queued job: `IsLocalOnlyCommunity`, `IsLocalOnlyObject`, `IsLocalOnlyPostID` and
`IsLocalOnlyActivity`.

They are applied at discovery and serialization (local-only objects, replies and
communities resolve to `404`), at the database (an activity row for a local-only
community and a fabricated delivery job for one are both rejected by the existing
guards), at enqueue and recipient expansion (`PlanDelivery` returns an empty plan
for a local-only activity, so no job or receipt is created), and at worker
execution (a leased job whose community is local-only is suppressed rather than
sent). Inbox dispatch treats an activity naming a local-only object as inert
rather than reporting it.

`federation_local_only_test.mygo` verifies that guessed object, replies and
community identifiers all return `404`, that the Person outbox excludes
local-only content from both its count and its items, that the predicates classify
communities and posts correctly, that an activity or delivery job referencing a
local-only community cannot be inserted, that a signed `Update` naming a
local-only identifier is rejected with a generic `unknown object` and changes
nothing, and that an inbound `Announce` of a local-only identifier is inert and
creates neither membership nor inclusion.

## Member-readable reads (stage 5.11)

A read has no body, so `VerifySignedGet` covers `(request-target) host date` and
`FormatGetSignatureHeader` advertises exactly that covered-header list; the
POST-oriented header set is unchanged. `SignedRequester` resolves the signer from
the presented `keyId`, requires the key to belong to that same actor, and returns
an actor identity only after the signature and freshness checks pass.

`GET /objects/{id}` resolves the object's hosting community: openly readable
communities serve as before, while a members-only community first requires
`MemberReadAllowed`, which re-evaluates the community's current read policy for
the signed actor. A non-member, an unrelated instance actor presenting its own
key, and a key that does not belong to the named actor are all denied with the
same uniform `404`. Because the signer is always the actor whose own key signed,
an instance key can only ever speak for the instance actor and is never a
delegation for a member at that server.

`/communities/{name}/outbox` is protected the same way when the community is
members-only, and its contents are the community's own objects rather than
objects authored by the group actor; a Group outbox therefore filters by
community. Member-authorized listings reuse the same reachability rules without
the `eligible_users` filter, since membership has already been proven.

`federation_protected_test.mygo` verifies an unsigned and a signed non-member
read both receive `404`, an unrelated instance key and a mismatched key are
denied, a signed member receives the object, an openly readable object needs no
signature, and a members-only collection is denied without a signed member and
served with one.

## Protected delivery (stage 5.12)

Migration `005_peer_capabilities.sql` records an explicit per-domain
protected-read capability; an unknown peer fails closed. `PlanRestrictedDelivery`
expands a member-readable activity to the community's current approved members
only: local members get a site receipt, colocated members get a receipt for their
own site, and remote members get an outbound job addressed to their own personal
inbox (`actorURI + "/inbox"`) and only when their domain has the capability.
Followers, a shared inbox and the Public audience are never used for restricted
content, so no non-member fan-out is possible and an incompatible peer receives
nothing rather than a downgraded copy.

Dispatch re-checks the same state: before transmitting, the worker reads the
community's current read policy and, for a members-only community, re-verifies
that the recipient is still an approved member. A revoked member's queued job is
suppressed with a recorded reason instead of being sent.

`protected_test.mygo` verifies that expansion addresses exactly the capable
member, the local member and the colocated member, that the incompatible peer and
the non-member receive no job or receipt, that the capable member's job targets
its personal inbox, and that revoking the member before dispatch suppresses the
queued delivery without contacting the peer.

## Host-authoritative state (stage 5.13)

The protected Commune profile is carried by a host-authored `Update` of the
Group: the embedded object names the group and carries `commune:policy` (read and
post) and `commune:members` (the authoritative approved list). A replica applies
it only when the signer is the group itself, so a peer cannot rewrite another
community's authorization, and only to a community it holds as a replica
(`host_site_id IS NULL`).

`ApplyCommunityPolicy` bumps `policy_version` and replaces the policy;
`ReplaceReplicaMembers` revokes everyone the authority no longer lists before
re-approving the new set, so a removed member fails its next authorization check
and new reads or deliveries stop. Tightening an openly readable policy returns a
result that explicitly states previously delivered public copies cannot be
recalled; a non-tightening update carries no such note.

`federation_state_test.mygo` verifies that a signed host state updates the
replica's read policy and member set, that a member the authority removed loses
membership, that a rival peer cannot rewrite the authorization, and that the
tightening response discloses the recall limitation while a later relaxation does
not.

Stage 5 is complete: discovery, transport, receipt, delivery, destination
handling, protected reads and protected delivery are implemented and covered by
PostgreSQL tests. Live multi-server interoperability remains the stage 8/9/10/11
work.

## Group federation (stage 6.1)

A Group actor now advertises its `followers` collection and an `attributedTo`
management collection at `{actor}/moderators`, listed through
`GET /communities/{name}/moderators` (the creator plus current administrators,
gated by the community read policy like every other protected read).

Following is policy-aware and separate from membership: `follows` records a
subscription while `community_members` records authorization. An openly readable
community accepts a subscription and replies with a signed `Accept`; a
members-only community accepts only from an approved member or a manager and
otherwise replies with a signed `Reject`, so restricted admission needs approved
access. `Undo` of a Follow marks the subscription `undone` and stops new
delivery without touching membership.

`federation_group_test.mygo` verifies the accepted open subscription and its
Accept, the rejected non-member subscription and its Reject with no membership
granted, the accepted subscription after approval, unsubscribe leaving membership
intact, the Group advertising both collections, `404` for an unsigned protected
management read, and the creator appearing in the open management collection.

## Submissions and nested Announce (stage 6.2)

An inbound `Create` addressed to a hosted federated Group is validated and then
wrapped in an `Announce` by that Group. The original Create payload is embedded
verbatim rather than re-encoded, so unknown properties and proofs survive
forwarding unchanged. Public communities fan the announcement out to current
subscribers; members-only communities use the protected expansion instead. A
blocked author, a community that does not permit the author to post, or a
local-only activity produces no announcement at all.

Ambiguous payloads are rejected before any storage: a repeated key inside the
same JSON object yields `400 ambiguous activity`. Detection tracks keys per
object depth and discards them when the object closes, so sibling objects may
reuse a key name, and escaped strings are handled.

`federation_announce_test.mygo` verifies the announced submission, verbatim
preservation of an unknown `extension` and a `proof`, the fan-out to a
subscriber, rejection of a duplicate-key payload, and that a blocked author's
submission is not announced.

## Inbound Group Announce (stage 6.3)

An inbound `Announce` is treated as a verified inclusion claim. The announcer must
be a Group we know (hosted or a replica), the wrapped Create must already be
stored, the Create must resolve to a post we hold, and the post's community must
be exactly that announcing Group's community. Anything else is ignored without
naming the referenced content, so an unrelated announcing actor cannot approve
another community's content.

Verification records a `collection_memberships` row with state `accepted`, the
Group as `authority_actor_uri`, `signed_activity` as the method, and the Announce
URI as evidence. The insert is idempotent per `(post, community)`, and this path
performs no delivery planning, so replaying the same Announce causes no duplicate
fan-out.

`federation_inclusion_test.mygo` verifies that a Group Announce confirmed against
the author's canonical copy records inclusion, that a replay leaves exactly one
row and unchanged delivery jobs, and that an unrelated Group announcing the same
Create records nothing.

## Group management activities (stage 6.4)

Inbound `Add` and `Remove` name a `target` community actor and an `object`
Person, with an optional `commune:role` of `member` (default) or `manager`. The
handler resolves the hosted community, re-evaluates authority for the signing
actor through the same access path used everywhere else, and applies the change
through the existing membership/administrator repositories, which audit each
action in community scope. Policy changes continue to use the Group `Update`
state path, and site/domain blocks use the site policy repository.

Authorization comes from current records: a community creator or administrator,
the hosting site's administrator, or an explicit deployment administrator. A
valid signature from an unrelated remote actor grants nothing, and an
unauthorized request is ignored without confirming the target's existence.

`federation_management_test.mygo` verifies that a remote community manager adds
a member, promotes a manager and removes a member, that a stranger's correctly
signed `Add` grants nothing, and that all three authorized actions are audited.

## Scoped peer removal (stage 6.5)

A Group `Remove` whose `object` is a post we hold, and whose `target` is that
post's own community, records a community-scoped removal: a
`collection_memberships` row in state `removed` with the Group as authority. The
shared post body, its author and its tombstone are untouched, so peer moderation
never erases the author's object or another community's presentation. An
`Announce` wrapping such a `Remove` is consumed through the same path, with the
announcer required to be the community's own Group.

Followers continue to require Group approval per the stage 6.1 admission policy,
so a subscription alone grants no restricted access.

`federation_removal_test.mygo` verifies the direct scoped removal and the
untouched shared body, that an unrelated community cannot remove another
community's post, and that an announced removal is consumed.

## Cross-server administration (stage 6.6)

Signed `Add`/`Remove` management requests are authorized against the current
host role records on every request, never against a cached or claimed role: the
creator or a current administrator of the target community, the hosting site's
administrator, or an explicit deployment administrator. A remote manager's
successful change is announced by the Group to eligible followers (or protected
members), wrapping the original management activity intact. Revoking the manager
row makes the next request a no-op, and a manager of one community has no
authority in another; site and deployment scope cannot be reached through
community management.

`federation_remote_admin_test.mygo` verifies authorized remote management, the
resulting Group announcement and follower delivery, that revocation blocks the
next action with no further announcement, and that management does not leak into
another community.

## Federated posting modes (stage 6.7)

Submission validation follows the community's posting policy: an openly readable
community accepts an eligible author, a members-posting community accepts only a
current approved member (a subscriber that is not a member cannot post), and a
member-readable community rejects any submission that was openly addressed to
the Public audience. Rejection leaves the received activity untouched and
produces no announcement, and member-readable announcements continue to use the
protected personal-inbox expansion.

`federation_modes_test.mygo` verifies all three modes, the non-member subscriber
denial, the public-addressed restricted rejection, and that the rejected
submission's stored payload is byte-identical to what was sent.

Chapter 6 is complete: Group collections, policy-aware follows, nested
Announce creation, verified inbound announcement, scoped management and removal,
cross-server administration, and all three posting modes are implemented and
covered by PostgreSQL tests.

## Discussion contexts (stage 7.1)

`storage.CreateDiscussionContext` gives a federated discussion a canonical context
identity (`{origin}/contexts/{id}`) and collection URI; a local-only discussion
receives an internal identity with no context or collection URI, matching the
database guard that forbids protocol data on local-only discussions.

`GET /contexts/{id}` serves an `OrderedCollection` of the posts that declare the
context, with `?page=N` returning an `OrderedCollectionPage` built from the same
object representations as community collections. A context without a URI, one
whose community is not federated, and an unknown identifier all return a uniform
`404`; a member-readable community's context additionally requires a signed
member read through the same path as protected objects and outboxes.

`federation_context_test.mygo` verifies the canonical collection identity and
total, the paged listing of the topic and reply, that a local-only discussion has
no protocol context, and that an unsigned read of a member-readable context is
denied while a signed member read succeeds.

## Context parsing (stage 7.2)

`federation.ParseContexts` reads only the AS2 `context` property. The JSON-LD
`@context` keyword is never treated as a discussion context, and `audience` is
decoded into its own list of URIs. A context may be absent, a string URI, an
object with an id, a Link with an href, a collection type, or an array mixing
those forms; every entry is returned as a declared reference with `Verified`
false. Parsing never resolves anything, so a resolution failure cannot reject the
containing activity, and duplicate or repeated context properties do not cause a
parse error.

`context_refs_test.mygo` verifies the `@context`/`context`/`audience` distinction,
string, collection, link and object classification, multiple mixed references, and
that a payload with repeated context properties still parses.

## Declared versus verified context membership (stage 7.3)

`post_contexts` records a declared association; `collection_memberships` records
the verified state with provenance. Locally authored attachments are accepted with
`local_authority`, while an inbound claim is recorded as `pending` until the
context authority verifies it. Context collections and counts join only an
`accepted` membership, so a forged claim cannot enter an accepted local
collection.

Removal is stateful: setting the membership to `removed` (by the authority) makes
the post immediately leave the context collection without touching the shared
post. `context_inclusion_test.mygo` verifies accepted and pending rows are stored
separately, that only the accepted post is counted, and that removal drops the
entry.

## Context-aware local interaction (stage 7.4)

A local reply keeps its direct `inReplyTo` parent while its optional
`context_uri` selects a possibly different discussion context. The API accepts
the context on `POST /api/v1/posts/{id}/replies`; persistence stores the parent
and declared context independently, and local-only communities reject a remote
context declaration before any protocol work occurs.

For a federated reply, the generated `Note` includes the declared ActivityStreams
`context`. `AnnounceLocalPost` resolves each declared remote context with the
same bounded fetch client and adds the document's `attributedTo` (or `actor`)
authority to the Group Announce recipients. Context authorities are deduplicated
against community followers and against each other before personal-inbox jobs
are planned. Request-scoped context is propagated through resolution and
transaction work instead of using a background context.

`federation_local_announce_test.mygo` verifies a reply whose parent belongs to a
local context but whose declaration joins a remote context, that the forwarded
Create retains the remote context URI, and that a context authority who also
follows the Group receives exactly one delivery job.

## Bounded discussion backfill (stage 7.5)

`POST /api/v1/contexts/{id}/backfill` resolves the context document, verifies its
`attributedTo` authority, maps that authority to a hosted or replica community,
and rechecks the requesting account's current read access before any import.
The caller must satisfy the ordinary authenticated mutation and CSRF checks.
Local-only contexts have no remote context URI and therefore cannot enter this
path.

Traversal starts at the context URI and follows only its advertised `first` and
`next` collection links. Each page is canonical (its `id` must match the fetched
location), at most ten pages and one thousand object identities are examined,
and visited pages and objects are deduplicated. Collection entries may be URI
strings, `id` objects, or `href` links; each object is then fetched from its own
canonical URI and its body id must match that URI.

An item is imported only when its Page/Note type, author, timestamp and direct
parent are valid. The parent must already name a post in the same community, so
a bounded pass never recursively crawls an unrelated object graph. Reception is
idempotent by object URI. Existing `site_posts.hidden_at` is preserved, and an
existing author tombstone is not refetched or restored.

Objects from context-less peers do not gain a `post_contexts` declaration. An
accepted `canonical_collection` membership and the `inReplyTo` chain provide
local navigation and collection inclusion without publishing an inference as a
remote context claim. `NavigationRoot` walks that local parent chain for reads
only, with a 64-hop bound.

`collection_traversal_test.mygo` covers mixed item forms, navigation links and
deduplication. `context_backfill_test.mygo` covers a three-page bounded pass,
idempotent replay, canonical membership without a declared context, local
`inReplyTo` navigation, and preservation of site hides and author tombstones.

## Protected context authority (stage 7.7)

Context retrieval, collection pages, membership evidence, counts and backfill
all resolve the current community policy on the request. For member-readable
federated contexts, signed GETs identify the requesting actor and admit only a
current approved member or a current community manager/site/deployment authority.
An unsigned request, unrelated instance key, non-member, revoked member or
revoked manager receives the same not-found response without object identities,
membership rows or counts.

Backfill performs the community access check before resolving the context
document. A denial therefore causes zero outbound fetches. A current member may
start traversal; revocation blocks the next attempt. Local-only contexts return
before fetch or import, so no remote synchronization can be initiated for them.

`federation_context_test.mygo` verifies signed member and manager success,
non-member and revoked-member/manager denial, non-disclosure of collection
evidence, zero fetches for denied protected backfill, and zero fetches for a
local-only context.

Chapter 7 is complete: context identities, parsing, declared-versus-verified
membership, independent reply grouping, bounded backfill, context-less
navigation, the Commune collection profile, and current protected-read checks
are implemented and covered by executable tests.

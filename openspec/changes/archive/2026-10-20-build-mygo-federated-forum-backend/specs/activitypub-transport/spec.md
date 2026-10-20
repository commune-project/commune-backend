## Purpose

Expose eligible ActivityPub resources with community access controls and process activities with verified authority, recoverable receipt, and reliable delivery.

## ADDED Requirements

### Requirement: Discovery and representations
The server SHALL provide WebFinger for eligible federated actors and canonical ActivityPub representations of Person and federated Group actors, objects, activities, and paginated collections. Federated actors SHALL advertise inbox, outbox, public key, and relevant collection endpoints as permitted by their access policy. Resource retrieval SHALL respect content negotiation, canonical ownership, read authorization, and deletion tombstones. Local-only communities SHALL expose no ActivityPub resources.

#### Scenario: Discover an actor
- **WHEN** a peer resolves a configured site's local account through WebFinger and retrieves the advertised actor URI
- **THEN** it receives a consistent actor identity, inbox endpoint, and actor-owned public key

### Requirement: Authenticated receipt and authority validation
Actor and site shared inboxes SHALL validate request signatures, body digests, bounded request freshness, and key ownership. Each activity SHALL undergo action-specific author or moderator authorization. A valid forwarding signature SHALL NOT by itself establish authorship of a nested activity; relayed content SHALL be independently verified through a supported proof or authenticated canonical origin retrieval.

#### Scenario: Signed forged update
- **WHEN** a correctly signed request attempts to update an object owned by an unrelated actor
- **THEN** the update is rejected without modifying the shared object

#### Scenario: Unverifiable nested author
- **WHEN** an authenticated community forwards an activity whose claimed author cannot be verified
- **THEN** the activity does not mutate shared author-owned state and its verification failure is recorded

### Requirement: Durable and recipient-aware idempotency
Accepted inbound work SHALL survive restart before successful acknowledgement. Repeated processing SHALL be idempotent by activity identity and recipient scope, while object identity SHALL be deduplicated independently. Duplicate reception SHALL NOT suppress delivery to a different eligible local site or actor. Conflicting reuse of an activity URI SHALL NOT overwrite previously accepted content.

#### Scenario: Duplicate activity with another recipient
- **WHEN** the same activity arrives for site A twice and subsequently for site B
- **THEN** site A's effects occur once and site B still processes its own eligible reception

### Requirement: Atomic durable delivery
Local mutations requiring federation SHALL persist their activities and outbound work atomically with the mutation. Delivery SHALL be signed by the correct site's actor, bounded, retried after transient failures, and recoverable after restart. Exhausted and permanent failures SHALL be visible to operators, and one unavailable peer SHALL NOT block other deliveries.

#### Scenario: Peer unavailable during publish
- **WHEN** publication commits but the destination is temporarily unavailable
- **THEN** the publication remains stored and queued delivery retries without creating another post

### Requirement: Bounded remote retrieval
Remote resolution SHALL enforce network destination restrictions against loopback, private, link-local, and metadata services; limits on time, bytes, redirects, recursion, and collection pages; and repeated checks after redirects and DNS resolution. Test-only local federation access SHALL require explicit isolated configuration.

#### Scenario: Redirect to a private destination
- **WHEN** a public actor URL redirects to an internal address
- **THEN** the retrieval is rejected before contacting that address

### Requirement: Complete local-only community exclusion
Local-only communities and associated metadata, members, posts, reactions, contexts, collections, counts, and links SHALL NOT participate in ActivityPub discovery, retrieval, inbox processing, outgoing activity creation, delivery, or synchronization. This SHALL apply even for valid members, valid transport signatures, public Person followers, and colocated sites. Public representations SHALL filter local-only records before pagination and counting. Inbound references SHALL NOT import, mutate, synchronize, or cause outbound responses about those resources. Dispatch SHALL suppress stale or fabricated jobs involving them.

#### Scenario: Private post by a publicly followed author
- **WHEN** an author with remote public followers publishes, edits, likes, or deletes a local-only community post
- **THEN** no related ActivityPub activity, public outbox entry, collection item, or remote delivery is generated

#### Scenario: Guessed local-only protocol resource
- **WHEN** a caller requests a local-only community, object, or context through ActivityPub or WebFinger
- **THEN** a uniform not-found result exposes no resource even if the caller has local community access

#### Scenario: Valid signed inbound targeting local-only content
- **WHEN** an otherwise authenticated peer references a local-only community in Follow, Create, Update, Announce, or context synchronization
- **THEN** the target is not processed for federation, no remote dependency is fetched for it, and no federation response reveals its existence

### Requirement: Member-readable federated delivery and retrieval
Member-readable federated communities SHALL authorize resource reads and delivery against current community membership or applicable verified management authority. Remote read requests SHALL establish the requesting actor or an explicitly authorized delegation; a valid server signature alone SHALL NOT grant access to every account on that server. Restricted activities SHALL NOT address the public audience or reach non-members through shared inboxes, author followers, relays, or conventional boosts. Local caches and collections SHALL enforce the same policy. Peers without verified restricted-access support SHALL receive no restricted content.

#### Scenario: Signed non-member fetch
- **WHEN** a non-member actor correctly signs a GET for a member-readable post or context collection
- **THEN** content, membership details, and counts are not disclosed

#### Scenario: Member revoked before queued delivery
- **WHEN** a member loses access after delivery is queued but before it is transmitted
- **THEN** the worker rechecks authority and suppresses that member's content delivery

#### Scenario: Generic peer instance key
- **WHEN** a peer presents its instance actor's signature without an authorized member delegation
- **THEN** membership of another actor at that instance does not authorize the fetch

### Requirement: Access-policy changes do not silently widen disclosure
Access-policy updates SHALL apply to new reads, mutations, collections, and pending deliveries. Tightening a federated read policy SHALL stop newly unauthorized access and delivery, but SHALL NOT be presented as erasing copies previously delivered publicly. Local-only versus federated participation SHALL NOT change through a read/post policy update.

#### Scenario: Tighten federation read policy
- **WHEN** an authorized manager changes an openly readable federated community to members-only reading
- **THEN** subsequent non-member reads and pending deliveries are denied while the management result states that previously delivered copies cannot be recalled

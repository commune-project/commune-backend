# discussion-context Specification

## Purpose

Implement FEP-7888 context grouping and participation while keeping declared relationships distinct from authoritative discussion membership.

## Requirements

### Requirement: Resolvable local discussion contexts
Topics in federated communities SHALL establish stable resolvable discussion contexts; authored replies participating in that discussion SHALL reference the same context and retain their direct inReplyTo. Eligible context representations SHALL expose their authority and a discoverable paginated canonical collection of accepted discussion objects under the community's read policy. Local-only topics SHALL retain internal discussion identities accessible through authorized local APIs without exposing ActivityPub contexts. Context identifiers SHALL be distinct in meaning from audience and JSON-LD @context.

#### Scenario: Traverse a local discussion
- **WHEN** a peer resolves a topic's context
- **THEN** it can identify the context authority and browse the accepted topic and replies through the advertised collection

### Requirement: Flexible remote context consumption
The system SHALL consume absent, unresolved, resolved non-collection, collection, and multiple context references. Objects SHALL be grouped by context identity when available without assuming every context is a collection. An absent context SHALL NOT invalidate otherwise supported content; an unresolved context SHALL retain its identifier without unbounded retries. Reply-parent ancestry SHALL remain separate from declared context grouping.

#### Scenario: Reply declares another context
- **WHEN** a valid reply points to a parent in context A but declares context B
- **THEN** the system retains the reply relationship and groups its declared context under B without silently rewriting it to A

#### Scenario: Multiple unresolved contexts
- **WHEN** a valid object declares two contexts that cannot currently be resolved
- **THEN** both identities are retained as unverified context associations and the object is not rejected solely for resolution failure

### Requirement: Authoritative membership verification
For an authoritative context with a recognized canonical collection, the system SHALL distinguish an object's context claim from proven inclusion. Inclusion SHALL be established through authenticated collection membership or a supported verified authority action and SHALL be invalidated by authoritative removal. Unverifiable claims SHALL be exposed as unverified and SHALL NOT automatically enter the authority's accepted collection.

#### Scenario: Forged local context claim
- **WHEN** a remote object claims a local discussion's context without acceptance by its authority
- **THEN** it does not appear in the canonical accepted discussion collection

### Requirement: Context-aware interaction
When a locally authored interaction joins a resolvable remote context, the system SHALL include the context authority in eligible delivery addressing in addition to the reply and community recipients. Delivery SHALL respect public visibility, access rules, and deduplication. Received interactions SHALL NOT be forced to inherit a parent's context when they explicitly choose another or omit one.

#### Scenario: Reply into a remote discussion
- **WHEN** an account replies within a remote context whose attributedTo authority is resolvable
- **THEN** the reply references that context and its activity is scheduled for the authority and other eligible recipients without duplicate deliveries

### Requirement: Bounded context synchronization
The system SHALL support bounded traversal of recognized canonical collections to import missing eligible discussion objects, validating each object's identity, authority, and requesting actor's read access. Restricted backfill SHALL use a currently authorized member or manager identity and preserve access scope. A discovered membership SHALL NOT override read controls, local site hiding, or a verified author-deleted object.

#### Scenario: Backfill after a missed reply
- **WHEN** an eligible site synchronizes a recognized remote discussion collection containing a previously missed reply
- **THEN** it imports that reply once and records its verified membership while preserving local moderation decisions

### Requirement: Discussion access inherits community scope
Context lookup, collection membership, reply traversal, counts, and synchronization SHALL enforce the hosting community's read policy. Local-only discussions SHALL perform no remote context resolution, delivery, or backfill. Member-readable federated contexts SHALL not expose content or inclusion evidence to non-members, even through a parent's replies collection or public author representation. Cross-context interactions SHALL NOT automatically widen access.

#### Scenario: Non-member resolves a restricted discussion
- **WHEN** a non-member requests a member-readable federated context or its collection pages
- **THEN** neither discussion items, membership evidence, nor counts are disclosed

#### Scenario: Local-only discussion synchronization requested
- **WHEN** a peer or local caller attempts ActivityPub backfill for a local-only discussion
- **THEN** the operation performs no remote fetch and exposes no ActivityPub collection


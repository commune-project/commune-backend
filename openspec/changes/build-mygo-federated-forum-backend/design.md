## Context

See `proposal.md` for motivation and `specs/` for behavior contracts. This repository currently contains only module and OpenSpec setup. The Go backend at `../../commune` is a reference for Actor, community, post, and reply concepts, not a compatibility contract. Its global context, incomplete federation wiring, and destructive demo startup must not be carried forward.

The local MyGO repository documents Go package interoperability, Option/Result boundaries, struct tags, and bootstrap generation. These support an infrastructure integration strategy, but the exact HTTP callback, SQL scan, transaction, and JSON representations require an early executable probe. No compiler changes are included in this change.

User decisions: independent accounts and authentication per site; one stored post per object identity within a shared database; no legacy compatibility; no categories; local/private communities with no ActivityPub synchronization; three read/post modes independent of federation; deployment superadministrator, site administrator, community creator, and community administrator scopes; remote creators and administrators for federated communities; member-readable federation distinct from local-only privacy; FEP-1b12 and FEP-7888; acceptance order Commune, Lemmy, Mastodon, Misskey.

## Goals / Non-Goals

**Goals:**

- Make tenant identity explicit at HTTP, authentication, repository, and delivery boundaries.
- Separate federation participation, community read/post policy, approved membership, subscriptions, and management authority.
- Exclude local-only content from every ActivityPub path, and constrain member-readable federation to verified eligible actors and peers.
- Separate immutable identity, current author-owned content, declared relationships, verified inclusion, and local policy.
- Use the same validation and idempotency rules for independent instances and sites colocated in one deployment.
- Keep domain rules in MyGO and infrastructure adaptation small and reviewable.
- Make interoperability evidence reproducible and bound claims to tested peer capabilities.

**Non-Goals:**

- No byte-content deduplication across unrelated object URIs, shared login identity, or automatic site-wide content sharing.
- No full JSON-LD reasoning engine, arbitrary remote context document loading, or assumption that context resolution grants permissions.
- No automatic legacy database conversion, synchronization of local-only communities, frontend, or emulation of another application's client API.
- No promise of peer-native group UI or optional extension parity where the peer lacks it.

Local-only and federated communities support all three read/post modes. Operator-provisioned accounts and manager-approved membership are planning defaults. Federation participation is fixed at creation for this change, while read/post policy is manageable. Tightening a previously public read policy cannot withdraw already delivered copies from remote databases; the management response and runbook state this limitation.

## Decisions

### 1. MyGO application with explicit Go infrastructure boundaries

Use MyGO for configuration orchestration, routing decisions, authorization, forum services, protocol parsing, federation dispatch, and worker state transitions. Prefer Go FFI imports for `net/http`, `encoding/json`, `database/sql`, context, time, and cryptographic libraries. If a callback or interface cannot be safely expressed, introduce a minimal adapter or inline Go boundary; do not move services into handwritten Go to bypass language problems.

Proposed package boundaries are `cmd/commune`, `internal/config`, `internal/http`, `internal/auth`, `internal/forum`, `internal/federation`, `internal/storage`, and `internal/jobs`. Names can change without changing capability contracts. Domain error and missing-value handling uses Result and Option; wire JSON receives explicit DTOs or maps rather than generated sum-type representations.

Generate through the documented default bootstrap pipeline and check in generated Go beside its MyGO source. CI regenerates and checks for drift before compiling and testing. Do not hand-edit generated files or silently fall back to the legacy compiler. Capture the compiler commit and toolchain version in build evidence.

Alternative: reuse old Go handlers and replace selected logic incrementally. Rejected because it retains implicit global state and incomplete contracts, while the user requests a fresh MyGO backend.

### 2. PostgreSQL with GORM repositories and explicit versioned SQL migrations

Use PostgreSQL through pinned GORM and PostgreSQL driver releases. Implement repository orchestration and models in MyGO, using generated Go structs with explicit GORM column tags and table selection. Require explicit site predicates and parameterized query values; GORM does not provide tenant authorization automatically. Use flat persistence records with Go-compatible nullable fields rather than persisting MyGO Option/Result variants through reflection.

Retain explicit versioned SQL migrations and their checksummed ledger. Never call AutoMigrate during normal serving or provisioning. database/sql may remain at the migration boundary via GORM's underlying connection pool. A publication's object mutation, immutable activity record, and outbound jobs must share the same explicit GORM transaction handle. Probe model mapping, query construction, transaction errors and MyGO FFI before accepting the persistence integration. PostgreSQL also stores sessions, inbound work, and delivery jobs, avoiding an initial Redis requirement.

Each server process can host multiple sites. Operators configure domain routing and canonical origins and explicitly provision site records and initial administrators. Normal serving requires a compatible migration version and never seeds or deletes data.

Alternative: use database/sql for every repository operation. Superseded by the user's decision to use GORM while retaining explicit SQL migrations. Redis remains unnecessary for the initial session and queue behavior. No legacy model or schema compatibility is implied by choosing GORM.

### 3. Site-scoped accounts and credentials

Resolve a normalized request authority to a configured SiteContext before account or forum access. Respect forwarded authority only from configured trusted proxies; generate canonical URIs from configured origins. Host aliases, if configured, route to one canonical identity and do not create alternate ActivityPub IDs.

Local accounts reference a site-owned Person actor. Enforce normalized username and optional email uniqueness within `site_id`. Store password hashes and actor private keys outside public actor representations. Use opaque random session tokens, stored as hashes with `site_id`, account, and expiry; cookies are Secure, HttpOnly, host-scoped, and paired with CSRF checks. Ordinary site roles never follow an account to another site; an explicitly assigned deployment role authorizes scoped administrative actions across hosted sites without turning its session into another site's user login. Authentication failures do not distinguish nonexistent accounts from incorrect passwords.

Public user following is separate from account authentication and community membership. A remote actor can follow a local Person and receive eligible authored public content without becoming a local login account.

Use explicit role assignments: deployment superadministrator manages hosted sites and communities; site administrator manages their site and hosted communities; creator and community administrator manage their specified community's members, metadata, policy, administrator assignments, and moderation. Audit elevated actions. These roles do not impersonate authors or grant higher-scope roles to community managers. Local-only community managers are owning-site accounts. Federated creator and administrator assignments use actor URIs and may be remote. A remote server administrator has no automatic authority over a community hosted here.

Alternative: one shared identity with site memberships. Rejected by the explicit independent-account decision.

### 4. Shared posts and separate reception and inclusion

Proposed logical relations:

| Relation | Identity and purpose |
| --- | --- |
| sites | Canonical origin and routing identity |
| actors | Unique canonical URI; optional local owning site; Person or Group metadata |
| accounts, sessions, deployment_roles, site_roles | Independent site login identities and explicitly scoped deployment/site administration |
| communities, community_members, moderators, follows | Owning site, immutable federation participation, read/post policies, creator actor, approved members, community administrators, and separate subscription state |
| posts | Unique federated object URI or stable local-only identity, author, hosting community/access scope, title, current content, parent, update and tombstone state |
| site_posts | Unique site/post reception with local visibility and policy state |
| post_audiences | Declared community associations, distinct from approval |
| discussion_contexts, post_contexts | Context identity, declared relationships, resolution and authority information |
| collection_memberships | Verified context/community inclusion, provenance, and removal state |
| reactions | Actor/object reaction identity and undo state |
| activities, activity_payloads | Unique activity identity and retained original payload needed for forwarding |
| inbox_receipts | Activity plus site/recipient processing state |
| delivery_jobs | Activity, signing actor, target inbox, retry state, and lease |

Use unique constraints and transactional upserts to converge concurrent object imports. Object URI comparison preserves path and query semantics; do not deduplicate by display URL, content hash, or aggressive URI rewriting. Reject conflicting authorship or activity identity reuse rather than replacing accepted state.

Shared storage is a deployment optimization, not a subscription or access mechanism. Site APIs query eligible `site_posts` and inclusion records and apply current community read policy for the acting identity; they never list all shared rows. Local-only posts use the same normalized storage without ActivityPub representations or cross-site reception. Federated member-readable objects retain their restrictions at every receiving site: a receipt is not a viewing entitlement. Public canonical resources are served only through their owning origin. Importing an eligible remote resource creates that site's reception record after validation and preserves the remote access scope.

Verified author updates change the shared current content without clearing site hides. Author deletion creates a replay-resistant tombstone. Moderator removal changes community/context inclusion, and site hiding changes only site visibility. Never cascade a local hide or context deletion into unrelated shared objects.

Exact received activity payloads are retained once per activity, not once per site. Payloads can contain historical embedded bodies needed for intact forwarding; this is protocol evidence, not additional logical posts. Reference one payload from receipt and delivery rows, reuse stored serialized artifacts, and define bounded retention for completed jobs without dropping payloads still needed by published activities. This preserves one normalized current post body per object while acknowledging unavoidable protocol snapshots.

Alternative: tenant-owned post tables or one `site_id` on each remote post. Rejected because both duplicate content or make multi-site reception impossible to express correctly.

### 5. Native forum objects and stable public routes

Publish eligible federated topics as Page and replies as Note, with Group audience, author attributedTo, and direct inReplyTo. Accept supported remote Note-based topics when addressed to an eligible federated community and permitted by posting policy; preserve original type and URI. Member-readable payloads omit Public addressing and are served or delivered only within approved access scope. Local-only topics and replies remain local records with no ActivityPub serialization.

Proposed canonical routes are `/users/{name}`, `/communities/{name}`, `/objects/{id}`, `/activities/{id}`, and `/contexts/{id}`, with advertised inbox, outbox, followers, moderators, replies, and collection-page routes. Use a site-level shared inbox. Local forum APIs use a documented versioned namespace such as `/api/v1` and return stable error categories and pagination cursors. Do not preserve the old backend's path shapes as a constraint.

Support community creation, topics, nested replies, author edits/deletion, likes, scoped management, community removal, and blocks. A new community belongs to its hosting site; its creator initially has member and creator authority. A hosting-authorized manager may assign verified remote creator or administrator identities to a federated community. This does not permit arbitrary remote creation on an unrelated site. Sanitization creates safe display content separately from retained protocol payload.

Model `federation_mode` as LocalOnly or Federated, `read_policy` as EligibleUsers or Members, and `post_policy` as EligibleUsers or Members. Expose only these three combinations:

| Mode | Local-only read / post | Federated read / post |
| --- | --- | --- |
| All users | Authenticated owning-site users / same users | Public read / eligible authenticated actors |
| Members only | Approved owning-site members / same members | Approved verified members / same members |
| All readers, member writers | Authenticated owning-site users / approved members | Public read / approved verified members |

Federated public reading includes ordinary anonymous ActivityPub discovery; posting always establishes actor identity. Management authority can authorize access and administration in its explicit scope and is audited. Community membership is independent of Follow subscriptions: Follow does not grant restricted read/post rights; a member can retain membership after unfollowing. Managers approve/remove members and administrators. Current membership, policy, and role checks run on every request and again at dispatch; revocation invalidates access caches, including access to a former member's own post. Reactions and other content mutations require appropriate access, and policy changes take effect without logging users out.

Local-only communities admit only owning-site identities and expose no anonymous or remote content. Their three modes must not be collapsed into a single members-only rule. Keep their metadata and content outside public listings and caches regardless of whether all local users can view them. Member-readable federated content receives analogous protection from non-members but can travel to approved remote members. Unauthorized reads return a uniform not-found result; authorized restricted APIs and protocol retrieval disable shared/public caching. Filter before pagination and counting.

Reject automatic cross-boundary replies, moves, imports, context assignments, and share/boost operations that expose local-only or member-readable identity/content in a wider scope. An explicitly authored new public post remains a separate object rather than conversion or automatic export of a restricted record. Never widen read scope by attaching another public community to a shared post.

Alternative: one public/private flag controlling both membership and federation. Rejected because site-wide local access, member-readable federation, and management roles are independent dimensions in the user's model.

Alternative: vary Page and Note type for the same local object by receiving software. Rejected as the default because receiver-dependent object semantics complicate identity and canonical verification. First test canonical Page delivery and supported ordinary sharing; any fallback must preserve the object URI and be documented and tested.

### 6. Durable transport and layered verification

Use RSA actor keys and interoperable HTTP request signing with digest and freshness checks as the initial transport profile. Pin signing dependencies and exact peer expectations during compatibility probes. Keep signing and verification replaceable for additional formats without altering domain rules.

Processing order: resolve recipient site; bound and read request; verify transport and key ownership; persist authenticated receipt and immutable payload; acknowledge durable acceptance; dispatch idempotently; apply action-specific authority checks; commit domain effects and outbound jobs. Invalid authentication is rejected immediately. Asynchronous domain rejection remains visible through processing state and a Reject activity when supported and appropriate.

A signed Group Announce establishes the forwarding actor, not the inner author's identity. Validate nested author state using a supported integrity proof or an authenticated canonical origin fetch whose identity and action match the received activity. Fail closed when neither can establish authority. Group approval and author mutation are separate checks. Colocated site delivery uses the same logical checks and receipt keys; it may avoid a network hop but must not bypass acceptance or create cross-site credentials.

Create eligible federated activity and jobs atomically with the mutation. Local-only mutations commit local domain/audit state and create no ActivityPub activities, payloads, notifications, or jobs. A central eligibility check evaluates federation participation and recipient read policy at serialization, enqueue, expansion, and dispatch. Suppress stale/fabricated local-only jobs and newly unauthorized restricted deliveries. Workers use expiring leases, bounded backoff/jitter, bounded Retry-After, and operator-visible failure states. Do not deduplicate member-readable delivery into a public shared-inbox broadcast; initially deliver to eligible actors' personal inboxes unless a pinned peer profile explicitly proves recipient-scoped shared-inbox behavior.

Local-only communities advertise no WebFinger entry, Group actor, key, inbox/outbox, followers/moderators collection, object/activity, or context endpoint. Public Person outboxes, liked/replies collections, ordinary Announce paths, public totals, and indices exclude both local-only and member-readable content. Local membership never enables ActivityPub for LocalOnly. Reject inbound references to local-only resources before domain import or remote dependency retrieval, without generating a federation response about them. These checks also apply to colocated-site delivery.

Member-readable federation is a separate protected profile. Verify signed GET identity against an approved member or community manager. A peer instance key is not a delegation for all its users; support actor-signed reads initially and only explicitly granted, revocable, requester-scoped delegation when demonstrably supported. Local member sessions can authorize the owning site's protected API, not public caching or anonymous protocol access. Collections, proofs of inclusion, context pages, activities, and moderation metadata inherit the community read policy.

The Group's minimal identity and inbox/key bootstrap may be discoverable to support membership requests, but do not expose restricted content, member/manager identities, counts, or collections to unauthorized callers. Approve member-readable subscriptions only after access is granted. Require supported peers to enforce recipient-level ACLs on cached objects and reads; otherwise refuse restricted delivery without downgrading it to public content. Do not follow remote context references in a local-only operation. Actor-signed management of a restricted federated community remains possible for its verified remote managers.

The host is authoritative for community membership, policy, creator, and administrator records. Commune peers preserve these access scopes through signed community announcements and policy state, which are explicit Commune protocol conventions documented alongside FEP behavior. A restricted activity must have eligible explicit recipients, no Public audience, and approved community/context association. Reject an openly addressed incoming payload to a member-readable community rather than altering the intact FEP-1b12 inner activity. Policy changes invalidate authorization caches and pending recipients; formerly public copies cannot be recalled. Remote servers that previously received restricted data remain a trust boundary, not a cryptographic erasure guarantee.

All remote actor, object, key, context, and collection fetches use the same restricted HTTP client: bounded bytes/time/redirects/depth/pages, DNS and connection destination checks, no private or metadata addresses, and checked redirects. Isolated test networks require explicit opt-in. Structured logs record identities and failure categories, not secrets.

Alternative: synchronous delivery inside API handlers. Rejected because peer downtime would turn committed publishing into ambiguous failures and lose work on restart.

### 7. FEP-1b12 groups

For federated communities, use Group actors, explicit audience, eligible Follow/Accept/Undo, intact nested Announce, and access-controlled outboxes. Open-read subscription admission does not grant membership in members-posting communities; member-readable admission requires approved membership or management access. Local-only communities have no ActivityPub subscriptions or announcements. Preserve raw JSON and unknown fields/proofs; reject ambiguous duplicate keys and public-addressed restricted submissions.

Community subscribers verify the outer Group, community association, and inner authorship independently. Record group approval only for a verified relevant announcement. Prevent repeated wrapping and distribution loops through activity/recipient receipts and community announcement identity.

Include the moderation profile for community management and Lemmy interoperability. Represent the creator distinctly and expose authorized creator/administrator actors through the attributedTo management collection under read policy. Verify remote actor identity and the host's current role assignment before accepting metadata/policy, membership, administrator Add/Remove, block, or scoped removal actions; remote management is required even when the manager's server differs from the host. Hosting-site administrators and deployment superadministrators operate through explicit audited host authority, never merely same-origin claims. Announce accepted management actions to eligible followers; receiving peers verify both the actor's role and the Group endorsement. Private member/role records remain confined to authorized recipients.

Lemmy-specific moderation encodings are normalized into scoped inclusion changes, not global author deletion. Do not assume every Delete from a moderator is author deletion.

Alternative: directly Announce the post object as the only group protocol. Rejected for native groups because FEP-1b12 requires preserving the received activity as the wrapper's object. Conventional object sharing remains a separate compatibility path where a microblog peer requires it.

### 8. FEP-7888 contexts with a documented Commune collection profile

Give each local federated discussion a context URI resolving to an OrderedCollection with community authority and audience, accepted topic/replies, and stable pagination. Member-readable collections require verified read authority; even membership evidence and counts are protected. Local-only discussions use internal identities and authorized local APIs with no ActivityPub collection, remote context resolution, or backfill. This direct-collection convention is Commune's profile, not a representation mandated by FEP-7888.

Publish the context on the topic and replies participating in that discussion. Parse ActivityStreams `context` separately from JSON-LD `@context` and `audience`. Preserve multiple remote context references and resolved IDs, and retain unresolved references as unverified. A missing context is acceptable. Derive a local navigation root from inReplyTo for context-less peers, but do not publish that inference as a remote authority's declared context or confirmed membership.

Maintain claimed associations separately from authoritative collection membership. Recognize direct Collection/OrderedCollection contexts and explicitly supported peer profiles; leave unfamiliar collection relations unresolved rather than guessing. Establish membership from the authority's authenticated collection or a verified action targeting it. Native Group acceptance updates its owned context collection transactionally and may provide verifiable announcement evidence when the context and community authority coincide; Announce from an unrelated Group proves no context membership.

Interactions participating in a resolved context address its authority as well as the reply author and community when eligible. Incoming replies with another context preserve both the parent relationship and declared grouping. Backfill is bounded, idempotent, and subject to site policy and object authority checks. Collection removal invalidates inclusion without globally deleting the shared post.

Alternative: store only a thread-root ID and call it FEP-7888. Rejected because it loses resolvable contexts, independent grouping, and the claim-versus-acceptance distinction.

### 9. Compatibility profiles and staged evidence

Keep target differences in parsing, representation, and transport profiles, not in tenant or authorization rules. Execute stages in the requested order, and keep all stages required in `tasks.md`.

The Commune stage tests all three local-only and federated access modes, full Group/context behavior, member-readable transport, and cross-server creator/administrator actions between independent databases and colocated sites. The Lemmy stage tests required public forum interactions and remote management supported by the pinned peer. Mastodon and Misskey stages test public Person interactions and supported community paths. Test nested envelopes and restricted access instead of assuming support. Unsupported restricted peers receive no such content; public sharing fallbacks never apply to member-readable objects. Retain canonical identity and intact native FEP-1b12 forwarding.

Use pinned deployments, isolated test networks, fixtures, and recorded assertions. Cover unknown fields, missing/multiple contexts, identity reuse, tampered forwarding, scoped deletion, all management scopes, and policy/membership/role revocation. Every peer profile verifies zero local-only leakage and zero restricted content disclosure to non-members through public followers, guessed IDs, counts, context backfill, inbound references, or retries. Commune must demonstrate positive member-readable federation and remote management; external reports explicitly state supported protected profiles and denied incompatible peers. Optional platform features remain extension-tolerance tests.

Alternative: claim compatibility from ActivityPub JSON examples alone. Rejected because live receiver behavior determines whether a post is displayed and replies return correctly.

## Risks / Trade-offs

- [MyGO FFI gaps] → Run executable HTTP/JSON/SQL/signing probes first, keep adapters minimal, and report compiler blockers without editing the compiler repository under this change.
- [Shared-state authorization mistakes] → Require explicit site-scoped repository access and exercise hostile cross-site sessions, IDs, moderation, and inbox routing.
- [Restricted or local-only content escapes through a secondary representation or queued job] → Check independent federation/read policies, current role/membership, and recipient ACL support at every boundary; test counts, Person collections, contexts, colocated transport, and retries.
- [Remote role claims or revocation drift] → Treat the community host as authority, verify signed role changes and Group endorsement, invalidate caches, and reject unrelated server-administrator claims.
- [Restricted peer cache or sharing leaks] → Require an explicit tested protected profile before delivery, use actor-scoped authorization and personal inboxes, and state that authorized remote servers remain trusted recipients of previously delivered data.
- [Nested activity forgery] → Authenticate both the forwarding Group and action authority; retain original payload and fail closed on unverifiable relays.
- [Peer limitations for Page or nested Announce] → Test pinned releases early, implement verified public interaction routes, and distinguish native group support from basic compatibility.
- [FEP text or peer behavior drift] → Record accessible authoritative revisions or clearly labeled mirror snapshots, content digests, retrieval dates, and pinned peer versions before implementation claims.
- [Protocol snapshots consume extra space] → Deduplicate payloads across sites and deliveries, retain only necessary historical protocol artifacts, and do not confuse logical post deduplication with zero duplication of wire content.
- [Out-of-order updates and removal] → Keep author versions, tombstones, membership provenance, and idempotent activity processing; reconcile ambiguous remote state through bounded canonical retrieval.
- [Large context collections or hostile links] → Enforce shared fetch limits, bounded backfill, resumable page cursors, and local hiding after synchronization.
- [Broad initial scope] → Implement and validate the staged tasks in dependency order; planning readiness does not imply all interoperability milestones are already achieved.

## Migration Plan

1. Pin and verify the local compiler/toolchain and protocol reference snapshots; complete the infrastructure probes.
2. Apply the initial schema to a new PostgreSQL database with an explicit migration command. No legacy data import is required.
3. Provision sites and accounts with explicit deployment/site roles; verify all local access modes, role scopes, and complete local-only exclusion before enabling federation.
4. Start the server and worker against a compatible schema with health checks and restricted remote fetching.
5. Run independent Commune and shared-database tests including member-readable federation and remote management, then external public profiles with restricted support gates and non-disclosure tests.
6. Enable the tested profiles for deployment and publish build, API, migration, and compatibility instructions.

Before schema upgrades, back up the database and stop or drain workers as needed. Prefer forward fixes; an operator-requested rollback restores a compatible database backup and binary together. Never automatically run destructive down migrations or clear data on application startup.

## References and Evidence Limits

- [ActivityPub](https://www.w3.org/TR/activitypub/).
- [FEP-1b12 canonical source](https://codeberg.org/fediverse/fep/src/branch/main/fep/1b12/fep-1b12.md); exploration used [the original-text mirror](https://helge.codeberg.page/fep/final/fep-1b12/) because direct source retrieval was unavailable.
- [FEP-7888 canonical source](https://codeberg.org/fediverse/fep/src/branch/main/fep/7888/fep-7888.md); exploration used [the original-text mirror](https://fep.swf.pub/fep/7888/fep-7888.html). A specific current source commit has not yet been verified.
- [Lemmy federation documentation](https://join-lemmy.org/docs/en/contributors/05-federation.html).
- [Mastodon ActivityPub](https://docs.joinmastodon.org/spec/activitypub/) and [security](https://docs.joinmastodon.org/spec/security/).
- [Misskey extensions](https://misskey-hub.net/ns/).
- Local MyGO `README.md`, `docs/compiler2/core.md`, and FFI tests. Bootstrap documentation and executable probes take precedence over older language documentation that describes the previous CLI default.

These references inform the proposed profiles; no live Commune, Lemmy, Mastodon, or Misskey compatibility test has been executed during planning. Pinning references and demonstrating those results are implementation tasks, not completed evidence.

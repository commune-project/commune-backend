## 1. Toolchain and protocol baselines

- [ ] 1.1 Record the local MyGO compiler commit and required Go toolchain, establish generation/build/test commands, and verify a minimal MyGO package builds through the default bootstrap pipeline.
- [ ] 1.2 Probe HTTP handlers and callbacks, JSON DTO and raw payload encoding, SQL scanning and transactions, and cryptographic FFI; verify each probe compiles and runs and document any minimal adapter required.
- [ ] 1.3 Pin FEP-1b12 and FEP-7888 reference revisions or explicitly labeled mirror snapshots with digests and dates, and deliver a normative requirement-to-test checklist without claiming an unverified current revision.
- [ ] 1.4 Select pinned PostgreSQL and peer releases or image digests and establish isolated federation test infrastructure; verify each service starts and its identity and transport prerequisites are recorded.
- [ ] 1.5 Create the MyGO package skeleton and generated-file workflow; verify regeneration followed by build and test succeeds without manual generated-code edits.

## 2. Runtime and persistent foundation

- [ ] 2.1 Implement validated site/origin/database/runtime configuration and trusted proxy settings; verify invalid origins and duplicate normalized domains fail before serving.
- [ ] 2.2 Add explicit migrations for sites, actors, accounts, sessions, deployment/site roles, and forum identities; verify initial migration, explicit superadministrator scope, and compatible schema detection.
- [ ] 2.3 Add migrations for community federation/read/post policies, creator assignments, approved members, community administrators, reception, audiences, contexts, collection membership, subscriptions, reactions, activities, receipts, and jobs; verify constraints and actor-URI assignments permit remote federated managers but reject cross-site local-only membership.
- [ ] 2.4 Implement explicit site, initial site administrator, and deployment superadministrator provisioning; verify repeated provisioning cannot replace credentials or implicitly escalate a site role.
- [ ] 2.5 Implement HTTP lifecycle, liveness/readiness, graceful shutdown, and redacted structured logging; verify restart preserves populated data and shutdown leaves unfinished work recoverable.

## 3. Site identity and authentication

- [ ] 3.1 Implement authority normalization, configured site routing, canonical URI generation, and trusted proxy handling; verify unknown hosts and spoofed forwarded hosts cannot select another site.
- [ ] 3.2 Implement site-local account creation/provisioning, password hashing, and username/email login lookup; verify identical usernames and emails can exist across sites with independent passwords.
- [ ] 3.3 Implement expiring revocable sessions, host-scoped secure cookies, CSRF protection, and logout; verify session replay across sites, missing CSRF, expiry, and logout rejection.
- [ ] 3.4 Implement site-scoped role checks, actor/domain blocks, and explicit site repository access; verify an administrator at A has no administrator permissions at B.
- [ ] 3.5 Implement independent federation/read/post policy checks for the three access modes; verify local-only non-members can read/write in all-site-users mode, cannot read in members-only mode, and can only read in site-read/member-post mode, with anonymous and cross-site callers denied.
- [ ] 3.6 Implement deployment superadministrator, site administrator, community creator, and community administrator authorization and audit; verify each scope and that community managers cannot grant higher-scope roles or edit another author's body.
- [ ] 3.7 Implement approved community membership, manager assignment/revocation, and manageable read/post policies with cache invalidation; verify removed members and revoked managers lose access on their next request despite valid sessions or historical authorship.

## 4. Shared forum objects and APIs

- [ ] 4.1 Implement canonical-URI post insertion and authoritative updates with transactional conflict handling; verify simultaneous reception at two sites stores one post and separate reception rows, while different URIs with identical text remain distinct.
- [ ] 4.2 Implement local-only/federated community creation, initial creator authority, all three access modes, and eligible topic/reply publication; verify immutable federation participation, independent policy updates, and parent/author/site ownership without categories.
- [ ] 4.3 Implement paginated community/discussion/object APIs and explicit remote import; verify unreceived shared IDs are inaccessible through another site's API.
- [ ] 4.4 Implement author editing and tombstone deletion; verify unauthorized edits fail and delayed Create cannot resurrect deleted content.
- [ ] 4.5 Implement safe textual rendering and protocol/display separation; verify unsafe remote HTML is neutralized while retained inbound payload remains unchanged.
- [ ] 4.6 Implement independent site hiding, community removal, and pending/accepted/rejected remote submission state; verify hiding at A preserves B's view and community removal does not become global deletion.
- [ ] 4.7 Implement Like and authenticated Undo with actor/object identity; verify duplicate likes and undo affect only the issuing actor's reaction.
- [ ] 4.8 Deliver the versioned local API contract with authentication, errors, and pagination examples; verify every documented initial forum operation against the running server.
- [ ] 4.9 Implement local-only topics, replies, reactions, edits/deletion, and management without ActivityPub artifacts; verify one local stored object, zero federation jobs, and no automatic cross-site reception for every local access mode.
- [ ] 4.10 Enforce inherited community access on object/context reads, lists, counts, and caches and reject wider-scope shares/moves/replies/imports; verify no local-only or member-readable identity/content escapes through public or shared-storage APIs.

## 5. ActivityPub discovery and transport

- [ ] 5.1 Implement site-correct WebFinger, Person/Group representations, canonical object/activity retrieval, tombstones, and content negotiation; verify advertised identities and keys match the owning site.
- [ ] 5.2 Implement bounded paginated inbox/outbox/followers and reply representations with appropriate visibility; verify pagination and canonical links through protocol fixtures.
- [ ] 5.3 Implement actor key provisioning, request signing, signature/digest/freshness verification, and key ownership checks; verify accepted signed requests and tampered body, stale request, and wrong-owner rejection.
- [ ] 5.4 Implement the restricted remote fetch client for actors, objects, keys, contexts, and collections; verify private-address, redirect, DNS destination, byte/time/depth/page limit, and explicit test-network cases.
- [ ] 5.5 Implement durable inbound receipt and recipient-aware dispatch using immutable activity payloads; verify duplicates at A do not suppress reception at B, conflicting activity URI reuse fails, and restart resumes accepted work.
- [ ] 5.6 Implement action-specific authority checks and nested activity verification through supported proof or authenticated canonical retrieval; verify a valid outer signature cannot authorize a forged inner Update/Delete.
- [ ] 5.7 Implement atomic mutation/activity/job persistence and leased delivery workers with retries and failure reporting; verify rollback schedules no jobs and crash or transient peer outage does not lose committed delivery.
- [ ] 5.8 Implement destination deduplication and colocated-site delivery with preserved recipient scopes; verify shared-inbox optimization retains all eligible local recipients and cannot bypass site policy.
- [ ] 5.9 Implement public Person Follow/Accept/Undo and ordinary object Announce ingestion; verify user-following delivery and boost ingestion remain distinct from group approval.
- [ ] 5.10 Add central local-only exclusion at discovery, serialization, inbox dispatch, activity creation, enqueue, recipient expansion, and worker execution; verify guessed identifiers, signed requests, public Person followers, shared collections/counts, colocated delivery, and fabricated/retried jobs reveal no local-only resources.
- [ ] 5.11 Implement actor-authorized member-readable GETs and protected collections/caches; verify member success, signed non-member denial, and generic instance keys without member delegation failing access.
- [ ] 5.12 Implement protected recipient expansion, personal-inbox delivery, peer capability gates, and dispatch-time membership/policy rechecks; verify zero Public addressing, no non-member fan-out, revoked-member suppression, and no restricted delivery to incompatible peers.
- [ ] 5.13 Implement host-authoritative membership/policy state synchronization for the protected Commune profile; verify remote replicas update authorization, policy tightening stops new access/delivery, and results disclose that already delivered public copies cannot be recalled.

## 6. FEP-1b12 group federation

- [ ] 6.1 Publish eligible Group audience and management collections and implement policy-aware Follow/Accept/Undo; verify membership is separate from following, restricted admission needs approved access, and unsubscribe stops new delivery without implicitly removing membership.
- [ ] 6.2 Implement community submission validation and intact nested Announce creation/outbox/fan-out; verify unknown properties and proofs survive forwarding, duplicate-key payloads are rejected, and blocked submissions are not announced.
- [ ] 6.3 Implement inbound Group Announce validation, verified inclusion, and forwarding-loop prevention; verify unrelated announcing actors cannot approve another community's content and replay causes no duplicate fan-out.
- [ ] 6.4 Implement creator/community-administrator assignments, Group metadata/policy changes, membership management, blocks, and scoped removal with hosting-site/deployment authority; verify signatures alone and unrelated remote server administration grant no rights.
- [ ] 6.5 Implement verified announced moderation consumption and scoped peer removal normalization; verify followers require Group approval and moderator removal never globally erases an author's shared object.
- [ ] 6.6 Implement signed cross-server creator and community-administrator management using current host role records and eligible Group announcements; verify remote authorized management succeeds, revocation blocks subsequent actions, and no site/deployment authority is granted.
- [ ] 6.7 Validate federated posting against all three access modes and protected addressing; verify non-member subscribers cannot post in members-posting communities and public-addressed restricted submissions are rejected without rewriting the original activity.

## 7. FEP-7888 discussion contexts

- [ ] 7.1 Implement federated context identities and policy-controlled OrderedCollection representations plus local-only internal discussion identities; verify authorized traversal and no ActivityPub context for local-only discussions.
- [ ] 7.2 Implement absent, unresolved, non-collection, collection, object/link, and multiple context parsing; verify context, audience, and JSON-LD @context remain distinct and resolution failure alone does not reject content.
- [ ] 7.3 Implement declared relationships versus verified membership with provenance and removal; verify a forged context claim cannot enter a local accepted collection and authoritative removal invalidates membership.
- [ ] 7.4 Implement context-aware reply addressing and independent parent/grouping handling; verify a reply can declare a different context and joining a remote context delivers to its authority without duplicate destinations.
- [ ] 7.5 Implement bounded idempotent discussion backfill and context-less peer navigation; verify missing replies can be imported while site hides and author tombstones remain effective.
- [ ] 7.6 Document the Commune direct-collection convention and its evidence rules; verify the document clearly separates Commune choices from FEP-7888 requirements and links executable fixtures.
- [ ] 7.7 Enforce current member/manager read authority on protected context resolution, membership evidence, counts, and backfill; verify signed member success, non-member/revoked-member denial, and zero remote synchronization of local-only contexts.

## 8. Commune interoperability milestone

- [ ] 8.1 Run two independently deployed Commune instances with separate databases; verify discovery, subscriptions, topics, nested replies, announcements, edits/deletion, likes/undo, moderation, and context backfill end to end.
- [ ] 8.2 Run a deployment with at least two independently authenticated sites sharing a database; verify one normalized post per URI, separate reception, cross-site session/ID isolation, and independent moderation.
- [ ] 8.3 Run restart/retry, out-of-order update/deletion, forged audience/context, and nested-author tampering scenarios; verify observable final states satisfy the transport and authority specs.
- [ ] 8.4 Run all three local-only and federated access modes and all four management scopes; verify positive remote member-readable retrieval/delivery/backfill and cross-server creator/administrator actions, plus policy/membership/role revocation and non-member non-disclosure.
- [ ] 8.5 Run local-only and protected leakage tests through public authors, discovery, shared inboxes, retries, links, caches, and collections; verify local-only data reaches no peer and protected data reaches only approved actors on tested peers before accepting the Commune milestone.
- [ ] 8.6 Publish Commune milestone evidence with compiler/build identities and protocol snapshots; verify all required Commune scenarios pass before accepting the Lemmy milestone.

## 9. Lemmy interoperability milestone

- [ ] 9.1 Implement and test pinned Lemmy actor, Page/Note, audience, title, Follow/Accept, nested Announce, and missing-context mappings; verify captured fixture round trips preserve canonical identities.
- [ ] 9.2 Run bidirectional live community subscriptions and topic/nested comment publication between Commune and Lemmy; verify both applications display correct authors, communities, titles, and parent links.
- [ ] 9.3 Run bidirectional authored updates/deletion, likes/undo, and community moderation removal; verify unauthorized and duplicate activity cases and scoped removal behavior.
- [ ] 9.4 Probe remote community management and protected-access support for pinned Lemmy, document demonstrated capabilities, and verify local-only exclusion and restricted delivery denial when the peer lacks the protected profile.
- [ ] 9.5 Publish Lemmy compatibility evidence with exact release and scenario results; verify required Lemmy cases pass before accepting the Mastodon milestone.

## 10. Mastodon interoperability milestone

- [ ] 10.1 Probe the pinned Mastodon release's Page display, Person follow, Note reply, and nested-versus-object Announce behavior; deliver captured evidence and implement a tested compatible delivery route preserving canonical identity and native group forwarding.
- [ ] 10.2 Run bidirectional discovery, Person follow/unfollow, public delivery, replies, edits/deletion, likes/undo, and ordinary boost ingestion; verify end-to-end application-visible results.
- [ ] 10.3 Verify explicit community-addressed Note submission and supported community distribution, plus duplicate and forged mutation cases; publish exact peer limitations without claiming unsupported native Group/context features.
- [ ] 10.4 Probe protected actor retrieval/cache and community management support for pinned Mastodon; verify documented limitations cannot trigger public fallback of local-only or member-readable content.
- [ ] 10.5 Publish Mastodon milestone evidence and regression fixtures; verify required public interaction cases pass before accepting the Misskey milestone.

## 11. Misskey interoperability milestone

- [ ] 11.1 Probe pinned Misskey actor, Note, Page, source/extension, and announcement behavior; verify the compatibility mapping retains unknown fields without changing authority or identity.
- [ ] 11.2 Run bidirectional discovery, Person follow/unfollow, public delivery, replies, edits/deletion, likes/undo, and ordinary Announce ingestion; verify end-to-end application-visible results.
- [ ] 11.3 Verify explicit community-addressed Note submission and supported community distribution, duplicate and forged mutation handling, and optional extension tolerance; publish exact peer limitations and tested release evidence.
- [ ] 11.4 Probe protected actor retrieval/cache and remote community management support for pinned Misskey; verify zero local-only leakage and no restricted delivery to a peer lacking validated access control.

## 12. Release verification and operator documentation

- [ ] 12.1 Add focused generation/build/test CI and integration profile commands; verify a clean regeneration has no drift and the full required acceptance matrix is reproducible.
- [ ] 12.2 Document configuration, all access modes and role scopes, explicit provisioning/migrations, protected-peer trust and revocation limits, local-only exclusion, recovery, retention, backups, and rollback; verify the runbook on fresh and populated databases.
- [ ] 12.3 Consolidate all four interoperability reports and capability-to-test evidence; verify no required target is silently deferred and fixture-only coverage is never labeled live compatibility.
- [ ] 12.4 Run strict OpenSpec validation and the completed implementation's declared checks; verify every task's evidence is recorded before marking this change complete.

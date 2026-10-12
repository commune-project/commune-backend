## Why

Commune needs a working MyGO backend for federated forums, with multiple independently authenticated sites sharing one server and database. The original Go backend provides domain references but is incomplete; a fresh implementation can establish explicit tenant boundaries and shared object storage without legacy compatibility constraints.

## What Changes

- Build the backend in MyGO using the local compiler at `../../mygo`, with Go interoperability for infrastructure boundaries.
- Serve multiple configured sites with independent accounts, authentication, permissions, and moderation.
- Store each ActivityPub post object once per database by canonical object URI, while keeping site reception, visibility, and moderation records separate.
- Provide forum APIs for accounts, local-only and federated communities, topics, replies, membership, subscriptions, editing, deletion, and moderation. Community categories are deferred.
- Separate federation participation from access policy. Local communities support all-site-users read/write, members-only read/write, and all-site-users read with members-only posting. Local/private communities never participate in ActivityPub, including colocated-site synchronization.
- Support analogous federated access policies, including member-readable federated communities distinct from non-federated local/private communities. Enforce verified membership for restricted retrieval, posting, context access, and delivery.
- Model deployment superadministrators, site administrators, community creators, and community administrators with explicit scopes. Federated community creators and administrators can manage across servers through verified actor authority.
- Implement ActivityPub discovery, actor and object retrieval, collections, authenticated inbound processing, and durable outbound delivery only where community federation and access policies permit.
- Implement FEP-1b12 group federation and FEP-7888 context handling with authoritative membership validation and access-aware collections; never downgrade restricted content to public delivery for compatibility.
- Deliver interoperability in order: independent Commune instances, Lemmy, Mastodon, then Misskey. Validate supported forum interactions against pinned releases rather than equating protocol support with complete application feature parity.
- Provide explicit database migrations, site/account provisioning, safe startup, and reproducible federation tests.

## Capabilities

### New Capabilities

- `server-runtime`: MyGO build workflow, configuration, provisioning, migrations, HTTP lifecycle, and operational visibility.
- `site-isolation`: Independent authentication, three community access modes, and deployment/site/community management scopes.
- `shared-forum-objects`: Shared storage and local/federated forum operations with separate community members, subscribers, reception, and inclusion records.
- `activitypub-transport`: Access-aware discovery, representations, authenticated receipt, durable delivery, restricted member federation, and complete local/private community exclusion.
- `group-federation`: FEP-1b12 following, membership-aware admission, intact forwarding, and cross-server community management.
- `discussion-context`: FEP-7888 context grouping and authoritative inclusion with inherited community access controls; local-only discussions remain outside ActivityPub.
- `federation-interoperability`: Ordered compatibility profiles, restricted Commune federation, cross-server management, and non-disclosure coverage.

### Modified Capabilities

None. There are no existing capability specifications in this repository.

## Impact

This introduces the server, database schema and migrations, local APIs, ActivityPub endpoints, delivery worker, tests, and deployment documentation in this repository. PostgreSQL is the proposed shared database; MyGO-generated Go and selected Go libraries provide HTTP, JSON, database, and cryptographic integration. The old Go backend and the MyGO compiler repositories remain reference dependencies and are not modified by this change.

No old database, endpoint, or client compatibility is required. Categories, frontend implementation, application-client API emulation, conversion between local-only and federated communities, and complete optional platform-feature parity are outside this initial change. All three access modes, non-federated local/private communities, restricted federated communities, and basic public interoperability with all four targets are in scope. Restricted interoperability with external software requires demonstrated access-control support; unsupported peers receive no restricted content.

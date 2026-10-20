## Why

The forum frontend cannot discover communities, show a site-wide discussion feed, restore reaction state, determine available actions, inspect management rosters, or load lossless editing values. Existing storage and authorization provide most underlying data, but the browser API does not expose a complete read contract.

## What Changes

- Add paginated community discovery and latest-topic APIs scoped to the resolved site and current reader.
- Add like counts, current-viewer like state, visible direct-reply counts, and actionable permissions to post representations.
- Expose current site/deployment roles through authentication responses and community membership, creator/manager identity, and effective permissions through community representations.
- Add paginated member and community-manager roster reads, including the creator, restricted to authorized community managers.
- Add an author-authorized source endpoint returning stored title and body for editing while preserving safe display representations.
- Document response fields, anonymous behavior, pagination, visibility, and revocation semantics, with HTTP and PostgreSQL acceptance tests.
- Defer public registration, search, notifications, profile editing, and attachment uploads.

## Capabilities

### New Capabilities

- `forum-browser-api`: Site-scoped discovery, aggregate discussions, viewer metadata, management rosters, and editable source contracts for the forum frontend.

### Modified Capabilities

None. This capability adds concrete browser contracts under the existing shared-object and site-isolation requirements without relaxing their boundaries.

## Impact

- Affects MyGO server routing/DTOs, storage read queries, authorization projections, authentication output, and API documentation.
- Adds `GET /api/v1/communities`, `GET /api/v1/topics`, community roster GET methods, and `GET /api/v1/posts/{id}/source`; existing response fields and mutation routes remain compatible.
- Uses existing communities, site reception, memberships, moderators, roles, posts, and reactions. No new service dependency or data migration is expected; measured query needs may justify indexes.
- Implementation must regenerate Go through the compiler and preserve the existing federation and tenant isolation acceptance suite.

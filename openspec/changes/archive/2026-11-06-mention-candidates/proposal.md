## Why

Composers can already resolve site-local `@username` mentions, but they have no browser API for discovering which accounts can be mentioned. The existing search endpoint covers posts and communities, public profiles require an exact username, and community rosters require management authority. This leaves mention autocomplete without a data source, especially when no post exists yet.

## What Changes

- Add an authenticated, database-backed `GET /api/v1/mentions/candidates` endpoint for mention autocomplete.
- Return site-local accounts and already stored remote Person Actors with a usable handle; never perform WebFinger, Actor, media, or other network discovery from this endpoint.
- Accept `q`, optional `limit`, and optional `community_id`. `community_id` is caller context only in this change and must not be required or used to filter candidates, because future microblog posts may have no community and notification eligibility is enforced later by `SetPostMentionsTx`.
- Exclude the requesting account, disabled local accounts, site-blocked actors, site-banned actors, and actors the viewer has personally blocked.
- Return only public projection fields: `actor_uri`, `acct`, `display_name`, and `avatar`.
- Keep existing mention resolution unchanged. Bare local `@username` already resolves to the local account in `SetPostMentionsTx`; this change adds candidate discovery only.

## Capabilities

### New Capabilities

- `mention-candidates`: authenticated, no-network lookup of mentionable local accounts and stored remote actors for composer autocomplete.

### Modified Capabilities

None.

## Impact

- New browser route, response DTO, request validation, and storage query.
- New server and storage tests using the existing MyGO test setup.
- No WebFinger or Actor fetch path, no outbound federation traffic, and no change to mention parsing or notification delivery.
- The frontend editor can consume the endpoint for autocomplete and update its help text to describe both local `@username` and remote `@username@domain` forms.

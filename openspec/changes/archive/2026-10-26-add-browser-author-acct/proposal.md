## Why

Browser post responses currently expose only `author_actor_uri`, so clients display a raw Actor URI instead of a readable handle or display name. The handle cannot be safely derived from an Actor URI path: remote implementations may host the Actor on one authority while publishing a different `username@domain` handle. The browser contract needs a verified `acct` plus the ActivityPub `name` projection.

## What Changes

- Add `actors.acct` as the persisted, verified `username@domain` handle for remote Person actors; local handles remain derived from the account username and canonical site authority.
- Add durable actor-handle resolution jobs when a site first encounters a remote Person author. Resolution runs asynchronously outside browser reads.
- Resolve a remote handle by retrieving the canonical Actor document and its WebFinger document, then requiring `preferredUsername`, Actor `id`, WebFinger `subject`, and the single ActivityPub `self` link to agree. Never derive the displayed handle from Actor URI path segments.
- Add a nested `author` object with `acct` and `display_name` to every browser post representation. Keep `author_actor_uri` for identity, permissions, editing, and fallback display.
- Bootstrap a blank remote `profiles.display_name` from the public Actor document's ActivityPub `name`; verified Person updates remain authoritative and are never overwritten by bootstrap data.
- Add operator-configurable, leased, retrying actor-handle workers with site block checks and the existing bounded federation fetch policy.
- Return empty strings for unknown `acct` or `display_name` rather than fabricating values; clients fall back to the display name, handle, or Actor URI in that order.

## Capabilities

### New Capabilities

- `actor-handles`: Verified Actor handle storage, asynchronous first-encounter resolution, profile-name bootstrap, worker durability, retries, and network/block boundaries.

### Modified Capabilities

- `forum-browser-api`: Post representations add a nested `author` object containing `acct` and `display_name` while retaining `author_actor_uri`.
- `user-profiles`: Allow a blank remote display name to be bootstrapped once from the canonical public Actor document without weakening verified Person-update authority.

## Impact

This change affects the PostgreSQL migration catalog, actor/profile storage, federation retrieval and WebFinger validation, participation-worker configuration and shutdown, browser post DTOs, frontend decoding and author display, and API/configuration documentation. It adds no new third-party dependency. Existing browser fields and mutation contracts remain compatible. The change does not add synchronous remote lookups to browser reads, does not guess handles from Actor URI paths, and does not backfill remote handles for actors that never reappear in received content.

## Context

See `proposal.md` for motivation. The current mention path has two layers: the server resolves remote candidates and applies discovery budgets, while the storage transaction resolves site-local handles and rechecks audience, blocks, and delivery capability before activating a mention. Bare local `@username` already works in that second layer, so this change must add discovery without altering mention activation.

The browser API already has content search, exact public-profile reads, and management-only community rosters. None of them provides a bounded actor lookup for a composer. The account and actor tables already contain the data needed for a read-only candidate query; no federation call is required.

## Goals / Non-Goals

**Goals:**

- Provide one authenticated, bounded, read-only endpoint for mention autocomplete.
- Include local accounts, stored remote Persons, and Persons hosted by another configured site when their handle can be derived without network access.
- Keep the endpoint independent of community context so future microblog posts can use it without a community.
- Reuse existing block, ban, and public-profile projections so the result agrees with the rest of the browser API.

**Non-Goals:**

- Changing mention parsing, local-handle resolution, notification eligibility, or `post_mentions` activation.
- Performing WebFinger, Actor, media, or any other outbound request.
- Resolving missing remote handles or repairing stale actor data.
- Adding pagination, global directory search, full-text account search, or rate limiting.
- Editing frontend code in this backend change.

## Decisions

### Dedicated route instead of extending content search

Add `GET /api/v1/mentions/candidates` and dispatch it beside the existing browser search route. Reusing `/api/v1/search?kind=accounts` would mix anonymous content search with an authenticated account lookup and would force the content-search contract to describe a different response shape and privacy boundary. A dedicated route keeps the autocomplete contract small and lets the endpoint grow independently.

The route requires a session before returning data, sets cache and referrer headers before validation, rejects non-GET methods, and validates `q` and `limit` before touching storage. Errors map to `401`, `400`, `405`, or `503` through the existing browser response helpers.

### Candidate set is local accounts plus stored actors with a derivable handle

The query unions three sources:

1. Non-disabled accounts of the resolved site, joined to their Person Actor and optional profile.
2. Remote Person Actors with `local_site_id IS NULL` and a non-empty stored `acct`.
3. Person Actors local to another configured site, joined to their account and that site's canonical origin to derive `username@origin`.

The union is deduplicated by Actor URI, preferring a stored verified `acct` over a derived origin. Actors without a stored or derivable handle are omitted; inventing a handle or resolving one over the network would violate the no-federation requirement.

Local candidates use the resolved site's canonical origin for `acct`. Remote candidates use the stored handle. `display_name` comes from the profile projection and falls back to the local username only for a local account without a profile. `avatar` is the stored avatar URL or an empty string. `actor_uri` is always included as the stable client key.

This deliberately treats the shared actor cache as the deployment's known-actor set. A handle stored through another colocated site can therefore appear. Only public profile fields are exposed, no content access or membership is granted, and a stricter site-scoped actor index can be added later without changing this endpoint's response contract.

### Community context is accepted but does not filter

`community_id` is accepted for caller context and forward compatibility. It is not required and does not trigger a community lookup, access check, membership check, or federation-mode filter. This preserves the future microblog case with no community and keeps the candidate endpoint out of the business of predicting whether a mention will notify or deliver. The existing post-save transaction remains the authority for audience, block, membership, inbox, and notification eligibility; an ineligible mention is dropped there.

The alternative, filtering by community read or post policy, was rejected because it would hide candidates that a later post context may legitimately use, would require duplicating policy logic, and would make the endpoint unusable for community-less posts.

### One bounded query with literal prefix ranking

A single parameterized query computes candidates, applies visibility filters, ranks, and limits. Visibility uses anti-joins against site actor blocks, site domain blocks, active site bans, and the viewer's person/instance blocks. Self, disabled local accounts, and disabled colocated-site accounts are filtered in the same query. No per-candidate `IsBlocked` call or per-candidate profile lookup is allowed.

The query escapes percent, underscore, backslash, and quote characters with the existing literal-search semantics. A candidate ranks as a prefix match when its handle or display name begins with the trimmed query; non-prefix matches follow. Ties sort by case-insensitive handle then Actor URI. The limit is applied after all filters and ordering. The result is a plain `{items:[...]}` array because autocomplete needs a bounded list, not a page.

### Storage module and response DTO stay small

Add a focused storage module for mention candidate search rather than growing the existing browser repository. It accepts the resolved site, viewer identity, query, and limit, validates its inputs again, and returns typed candidate rows. A small server DTO converts those rows to the JSON contract. This keeps the handwritten module bounded and makes the query independently testable.

## Risks / Trade-offs

- [Shared actor cache can expose a remote handle stored through another colocated site] → Return only public handle, display name, avatar, and Actor URI; grant no content or membership access. If strict site isolation is later required, add a site-scoped actor association and filter the remote branch.
- [Two-character queries enable account enumeration] → Require authentication, cap the result at 20, rank prefix matches first, and keep the endpoint read-only. Rate limiting is deliberately deferred.
- [Display-name matching can be slower than handle-prefix matching on a large database] → The result is capped and the query is bounded; add an expression or trigram index only if measurements justify it.
- [A stored remote actor may be suggested but dropped at post-save time] → This is intentional. The candidate list is a suggestion surface, and the save transaction remains the authority for notification and delivery eligibility.
- [Ignoring `community_id` may surprise a client expecting community filtering] → Document the parameter as optional context and add context-aware ranking later without changing candidate inclusion.

## Migration Plan

No schema migration is required; the endpoint reads existing account, actor, profile, site, block, and ban tables. Deploy the route and storage query, then let the frontend adopt it. Rollback is removing the route and its tests; no persistent state is written by the feature.

## Open Questions

None that change the specs or task breakdown. A site-scoped actor index and request rate limiting are explicitly deferred follow-ups.

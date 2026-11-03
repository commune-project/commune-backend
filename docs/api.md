# Local HTTP API (v1)

Every request resolves its site from the HTTP authority. JSON responses use
`application/json`; failures return `{"error": "<reason>"}` with `400`
invalid input, `401` unauthenticated, `403` forbidden or CSRF, `404` not found,
`405` wrong method, `409` object conflict, or `503` storage unavailable.
Unauthorized restricted reads return `404` so metadata and counts do not leak.

## Authentication

Mutating requests require the browser session cookie, an `Origin` matching the
resolved site's HTTPS origin, and an `X-CSRF-Token` header carrying the CSRF
cookie value. Without a session the response is `401`; with a bad origin or CSRF
it is `403`. Ordinary reads accept an optional session; anonymous callers see only
publicly readable content. Roster and editing-source reads require a session.
Requests with JSON bodies must send `Content-Type: application/json`
with no trailing data, or they are rejected with `400`.

The auth endpoints (login, session, logout) are described in
[authentication.md](authentication.md).

## Communities

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| GET | `/api/v1/communities?limit=&offset=` | | 200 community page |
| POST | `/api/v1/communities` | `name, title, mode, read_policy, post_policy`, optional `follow_policy` | 201 community |
| GET | `/api/v1/communities/{id}` | | 200 community |
| GET | `/api/v1/communities/{id}/topics?limit=&offset=` | | 200 page |
| POST | `/api/v1/communities/{id}/topics` | `title, body` | 201 post |
| PUT | `/api/v1/communities/{id}/policy` | `read_policy, post_policy`, optional `follow_policy` | 204 |
| POST/DELETE | `/api/v1/communities/{id}/follow` | | 204 |
| GET | `/api/v1/communities/{id}/follow-requests?limit=&offset=` | | 200 pending follow page |
| POST | `/api/v1/communities/{id}/follow-requests/{actor}` | `state` | 204 |
| GET | `/api/v1/communities/{id}/members?limit=&offset=` | | 200 member roster page |
| GET | `/api/v1/communities/{id}/managers?limit=&offset=` | | 200 manager roster page |
| POST/DELETE | `/api/v1/communities/{id}/members` | `actor` | 204 |
| POST/DELETE | `/api/v1/communities/{id}/managers` | `actor` | 204 |
| POST/DELETE | `/api/v1/communities/{id}/removals` | `post_id` | 204 |
| POST | `/api/v1/communities/{id}/submissions` | `post_id, state` | 204 |

`mode` is `local_only` or `federated` and is fixed at creation. `read_policy`
and `post_policy` are `eligible_users` or `members`; the only valid pairs are
all-users/all-users, members/members, and all-users-read/members-post. A
community object carries `id, name, title, description, federation_mode,
read_policy, post_policy, follow_policy, follower_count,
actor_uri (federated only) and host_site_id`, plus `viewer` relationship flags
and current `permissions`.

`follow_policy` is `open`, `members`, `approval`, or `disabled`. Creation
defaults to `open` for `eligible_users` read policy and `members` for `members`
read policy. Policy updates require current community management authority and
CSRF, and do not delete existing follows or memberships.

`POST /follow` applies the hosting community's current policy. `open` accepts
immediately; `members` requires membership or management; `approval` creates a
pending request for a non-member; `disabled` returns
`403 feature_disabled`. Operations are idempotent. `DELETE /follow` remains
available after new follows are disabled. Unknown, unreceived, or unreadable
communities return `404`.

The pending roster requires community management authority. Its decision path
URL-encodes the Actor URI. `state` is `accepted` or `rejected`; repeated equal
decisions are idempotent and conflicting decisions return `409`. Approval
atomically accepts the follow and grants membership. Rejection grants neither
membership nor read access. Existing pending rows remain reviewable after a
policy change, while new follows use the new policy.

Community responses expose `viewer.is_following`, `viewer.follow_state` in
`none|pending|accepted|rejected|undone`, and `viewer.can_follow`. The accepted
count is not disclosed to anonymous callers or non-manager readers of a
members-only community. Anonymous follow state is `none`.

## Posts

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| GET | `/api/v1/topics?limit=&offset=` | | 200 latest topic page |
| GET | `/api/v1/posts/{id}` | | 200 post |
| GET | `/api/v1/posts/{id}/source` | | 200 stored editor title/body and version |
| PATCH | `/api/v1/posts/{id}` | `title, body` | 200 post |
| DELETE | `/api/v1/posts/{id}` | | 204 |
| GET | `/api/v1/posts/{id}/replies?limit=&offset=` | | 200 page |
| POST | `/api/v1/posts/{id}/replies` | `body`, optional `context_uri` | 201 post |
| POST | `/api/v1/posts/{id}/vote` | `score` | 204 |
| POST/DELETE | `/api/v1/posts/{id}/likes` | | 204 |
| POST | `/api/v1/posts/{id}/import` | | 201 post |
| POST/DELETE | `/api/v1/posts/{id}/hide` | | 204 |
| POST | `/api/v1/contexts/{id}/backfill` | | 200 counts |

A post carries `id, community_id, object_type, title (topics only), body,
author_actor_uri, author, parent_id (replies only), authored_at, updated_at and
deleted`, plus `score`, `upvotes`, `downvotes`, `voted_by_me`, compatibility
`like_count`, `liked_by_me`, `saved_by_me`, `read_by_me`, `hidden_by_me`,
site-visible direct `reply_count`, and current action `permissions`. `author`
contains `acct` and `display_name`; both are empty when unknown, and
`author_actor_uri` remains authoritative. `body` and `title` are rendered for
display; see
[rendering.md](rendering.md). A page is `{items, limit, offset}`. `limit`
defaults to 20 and must be within the configured maximum; `offset` is
non-negative. Topics require a title; replies must omit it. A reply's optional
`context_uri` declares a discussion context independently of its parent; the
parent relationship remains the one named by the request path. `import` records
this site's reception only when the caller may currently read the object, and
`hide` is a site-administrator action.

### Votes and vote settings

`POST /api/v1/posts/{id}/vote` accepts `{"score":1}`, `{"score":-1}`, or
`{"score":0}` for upvote, downvote, and clear. `voted_by_me` is one of `-1`,
`0`, or `1`; `score` is `upvotes - downvotes` after applying the resolved
site's current direction settings; `like_count` remains an alias for active
upvotes. A repeated score is idempotent. Existing `POST` and `DELETE` like
requests remain aliases for upvote and clear.

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| GET | `/api/v1/site/vote-settings` | | 200 `upvotes_enabled, downvotes_enabled` |
| PUT | `/api/v1/admin/vote-settings` | at least one boolean setting | 200 full settings |

The public settings read defaults both directions to `true` when no row exists.
The administrator update is site scoped, requires CSRF and same-origin checks,
and accepts partial updates such as `{"downvotes_enabled":false}`. Unknown
fields, non-booleans, and empty bodies return `400`; an account without site or
deployment authority receives `403`.

A disabled direction is excluded from aggregates, personal vote state, ranking,
and new mutations. New votes and the corresponding like alias return
`403 feature_disabled`; clearing an existing vote remains allowed. Historical
rows are retained and count again if the direction is re-enabled. Vote
mutations return `400` for invalid input, `401` without a session, `403` for
origin/CSRF or a disabled direction, and `404` when the target is missing,
unreceived, deleted, hidden, or unreadable.

`GET /api/v1/topics` and
`GET /api/v1/communities/{id}/topics` accept `sort=new`, `old`, `top`, `hot`, or
`controversial`; topic listings default to `new`. Reply listings accept `new`,
`old`, `top`, or `controversial` and default to `old`. Filters run before
pagination, and authored time plus ID provides deterministic tie-breaking.

## Mention candidates

| Method | Path | Success |
| --- | --- | --- |
| GET | `/api/v1/mentions/candidates?q=&limit=&community_id=` | 200 `{items:[...]}` |

`q` is required and contains 2–64 Unicode code points; `limit` defaults to 8
and is capped at 20. `community_id` is optional context and does not filter
results, so the endpoint also works for future community-less posts. The
endpoint requires a session, returns `401` without one, `400` for invalid
input, and `405` for non-GET methods. Responses are `no-store` and use
`Referrer-Policy: no-referrer`.

Each item contains `actor_uri`, `acct`, `display_name`, and `avatar`; missing
strings are empty rather than null. `acct` is the full `username@domain`
handle. Local accounts without a profile fall back to the username for
`display_name`. The endpoint returns the resolved site's local accounts plus
stored remote Person Actors with a usable handle, including accounts hosted by
another configured site. Self, disabled accounts, site-blocked or banned
actors, and the viewer's personal person/instance blocks are excluded. It does
not perform WebFinger, Actor, or media discovery and does not enqueue delivery
or notification work; handles that are not already stored are omitted. In the
composer, `@username` mentions a local account and `@username@domain` mentions
a remote account.

## Reports, moderation log, and bans

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/api/v1/reports` | `target_kind, target_id, reason`, optional `community_id` | 201 or 200 repeat |
| GET | `/api/v1/reports?state=&community_id=&limit=&offset=` | | 200 report page |
| POST | `/api/v1/reports/{id}/resolve` | `state`, optional `note` | 204 |
| GET | `/api/v1/modlog?community_id=&limit=&offset=` | | 200 modlog page |
| POST/DELETE | `/api/v1/communities/{id}/bans` | `actor, reason, expires_at` | 204 |
| POST/DELETE | `/api/v1/admin/bans` | `actor, reason, expires_at` | 204 |

Reports accept target kinds `post`, `community`, and `person`. Reasons contain
1–1000 Unicode code points. A readable target is rechecked at submission; the
caller cannot report their own identity and unreadable targets return 404. The
same reporter can hold one open report per target: the first insert is 201 and
an idempotent repeat is 200. Report listing and resolution require community
management for community-scoped reports, site administration for site scope, or
deployment authority for deployment scope. Resolution states are `resolved` and
`rejected`; repeating the same decision is idempotent and a conflicting decision
returns 409.

The moderation log is newest first and append-only. It records report
resolution, post hide/unhide, community removal/restore, community ban/unban,
and site ban/unban. Community managers see only their scoped actions; site and
deployment administrators may read the wider site scope. Rows expose actor,
action, target kind/id, optional community, reason, and timestamp.

Bans accept an Actor URI, a non-empty reason, and optional RFC 3339
`expires_at`. An absent expiry means indefinite. Community bans block posting,
replying, voting, and mentions in that community while active. Site bans block
authentication and interaction across the resolved site, revoke existing
sessions, and do not alter the account's independent disabled flag. Expiry takes
effect automatically; unbanning an absent active ban returns 404. Every
successful ban or unban writes a moderation log row and queues an eligible
local-account notification. Report-resolution notifications use target kind
`report` with the report ID as `target_id`; ban notifications use target kind
`moderation` with the affected Actor URI. They remain hidden when the report
target becomes unreadable or the represented ban is no longer active.

## Account content state

| Method | Path | Success |
| --- | --- | --- |
| POST/DELETE | `/api/v1/posts/{id}/save` | 204 |
| POST | `/api/v1/posts/{id}/read` | 204 |
| POST/DELETE | `/api/v1/posts/{id}/hide-for-me` | 204 |
| GET | `/api/v1/account/saved?limit=&offset=` | 200 post page |
| GET | `/api/v1/account/read?limit=&offset=` | 200 post page |
| GET | `/api/v1/account/hidden?limit=&offset=` | 200 post page |
| GET | `/api/v1/account/liked?limit=&offset=` | 200 post page |

These routes require a current-site session and CSRF on mutations. State is
per account and site, and mutations are idempotent. Current read access is
rechecked before every listing and mutation. Personal hides do not alter
`site_posts.hidden_at`; direct detail may still return a personally hidden post
with `hidden_by_me: true`.

## Personal blocks

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| GET | `/api/v1/account/blocks` | | 200 block list |
| POST/DELETE | `/api/v1/account/blocks` | `kind, target` | 204 |

`kind` is `person`, `community`, or `instance`. Person targets are canonical
Actor URIs, community targets are community IDs, and instance targets are
normalized hostnames. Self blocks, the resolved site's own instance, malformed
targets, and unknown/unreadable communities return 400. Adds/removes are
idempotent and only affect the authenticated account at the resolved site.

## Password reset and change

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/api/v1/auth/password/reset` | `email` | 202 |
| POST | `/api/v1/auth/password/reset/confirm` | `token, password` | 204 |
| POST | `/api/v1/auth/password/change` | `current_password, new_password` | 204 |

Reset request is generic for valid addresses and is available when registration
is disabled. Rate limits return 429 with `Retry-After`. Confirmation consumes a
single-use site-scoped token and revokes all sessions. Password change requires
a current session, origin, and CSRF, and revokes other sessions while preserving
the current one. See [participation-api.md](participation-api.md).

See [Forum browser API](forum-browser-api.md) for complete viewer/permission
fields, discovery scope, sorting, roster privacy, source editing examples,
count semantics, and revocation behavior.

## Example

```
POST /api/v1/communities
{"name":"news","title":"News","mode":"federated","read_policy":"eligible_users","post_policy":"eligible_users"}

POST /api/v1/communities/news-id/topics
{"title":"Hello","body":"first post"}

GET /api/v1/communities/news-id/topics?limit=20&offset=0
```

`forum_test.mygo` drives login, community and topic creation, pagination and its
bounds, object read, cross-site denial of an unreceived id, nested replies and
their listing, author edit, like/undo idempotency, missing CSRF, missing
session, and non-JSON rejection against the real HTTP handler with PostgreSQL.
`TestPostgresForumModerationHTTP` additionally drives site-admin hide/unhide with
non-administrator rejection, `PUT` policy updates including an invalid
combination, member and manager add/remove with invalid-identity rejection,
community removal/restore, rejected/accepted/bogus submission states, and a
foreign session attempting site moderation.

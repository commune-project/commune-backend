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
it is `403`. Reads accept an optional session; anonymous callers see only
publicly readable content. Requests must send `Content-Type: application/json`
with no trailing data, or they are rejected with `400`.

The auth endpoints (login, session, logout) are described in
[authentication.md](authentication.md).

## Communities

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/api/v1/communities` | `name, title, mode, read_policy, post_policy` | 201 community |
| GET | `/api/v1/communities/{id}` | | 200 community |
| GET | `/api/v1/communities/{id}/topics?limit=&offset=` | | 200 page |
| POST | `/api/v1/communities/{id}/topics` | `title, body` | 201 post |
| PUT | `/api/v1/communities/{id}/policy` | `read_policy, post_policy` | 204 |
| POST/DELETE | `/api/v1/communities/{id}/members` | `actor` | 204 |
| POST/DELETE | `/api/v1/communities/{id}/managers` | `actor` | 204 |
| POST/DELETE | `/api/v1/communities/{id}/removals` | `post_id` | 204 |
| POST | `/api/v1/communities/{id}/submissions` | `post_id, state` | 204 |

`mode` is `local_only` or `federated` and is fixed at creation. `read_policy`
and `post_policy` are `eligible_users` or `members`; the only valid pairs are
all-users/all-users, members/members, and all-users-read/members-post. A
community object carries `id, name, title, description, federation_mode,
read_policy, post_policy, actor_uri (federated only) and host_site_id`.

## Posts

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| GET | `/api/v1/posts/{id}` | | 200 post |
| PATCH | `/api/v1/posts/{id}` | `title, body` | 200 post |
| DELETE | `/api/v1/posts/{id}` | | 204 |
| GET | `/api/v1/posts/{id}/replies?limit=&offset=` | | 200 page |
| POST | `/api/v1/posts/{id}/replies` | `body`, optional `context_uri` | 201 post |
| POST/DELETE | `/api/v1/posts/{id}/likes` | | 204 |
| POST | `/api/v1/posts/{id}/import` | | 201 post |
| POST/DELETE | `/api/v1/posts/{id}/hide` | | 204 |
| POST | `/api/v1/contexts/{id}/backfill` | | 200 counts |

A post carries `id, community_id, object_type, title (topics only), body,
author_actor_uri, parent_id (replies only), authored_at, updated_at and
deleted`. `body` and `title` are rendered for display; see
[rendering.md](rendering.md). A page is `{items, limit, offset}`. `limit`
defaults to 20 and must be within the configured maximum; `offset` is
non-negative. Topics require a title; replies must omit it. A reply's optional
`context_uri` declares a discussion context independently of its parent; the
parent relationship remains the one named by the request path. `import` records
this site's reception only when the caller may currently read the object, and
`hide` is a site-administrator action.

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

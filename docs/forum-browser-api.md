# Forum browser API

Requests resolve the site from the configured HTTPS authority. Authentication
uses the cookies described in [authentication.md](authentication.md). All browser
responses use `Cache-Control: no-store`; all JSON property names below are stable.
Existing mutation payloads and safe display fields remain supported.

| Read | Response | Access |
| --- | --- | --- |
| `GET /api/v1/communities` | Community page | Current-site readable communities |
| `GET /api/v1/communities/{id}` | Community | Current-site readable community |
| `GET /api/v1/topics` | Latest topic page | Current-site received/readable topics |
| `GET /api/v1/communities/{id}/topics` | Topic page | Community read permission |
| `GET /api/v1/posts/{id}` | Post | Site reception, visibility and read permission |
| `GET /api/v1/posts/{id}/replies` | Threaded reply page | Same as post read |
| `GET /api/v1/communities/{id}/members` | Member roster page | Hosted community management authority |
| `GET /api/v1/communities/{id}/managers` | Manager roster page | Hosted community management authority |
| `GET /api/v1/posts/{id}/source` | Stored editor values | Current readable, visible, non-deleted post; author editing authority |

## Pagination and visibility

All pages accept `limit` (default 20, positive, at most the configured maximum)
and `offset` (default 0, nonnegative). Invalid numbers or bounds return 400.
Every page has `items`, `limit`, and `offset`; exhausted pages have `items: []`.
No total count is promised. Offset pagination can shift during concurrent writes.

Community discovery sorts by name ascending then ID ascending. It includes
readable communities hosted here and remote replicas represented by posts this
site has received. Another colocated site's hosted communities are not discovery
candidates merely because they share a database. Anonymous discovery contains
public federated communities only. Authenticated local-only discovery remains
restricted to eligible site users or applicable audited administration.

Latest topics default to `sort=new` (authored time descending, ID ascending).
Community topics use the same default. Both accept `new`, `old`, `top`, `hot`,
and `controversial`; score-based modes exclude directions disabled by the
resolved site. Access filtering occurs before pagination. Topics and replies
exclude deleted objects, site hides, personal hidden rows, blocked authors,
communities, or instances, and removed/rejected community inclusion. Latest
topics require site reception and never trigger import or network discovery.

## Community representation

Existing fields remain: `id`, `name`, `title`, `description`, `federation_mode`,
`read_policy`, `post_policy`, optional `actor_uri`, and `host_site_id` (empty for
a remote replica). Creation, detail and discovery add:

```json
{
  "viewer": {
    "is_member": false,
    "is_creator": false,
    "is_manager": false,
    "management_scope": "site"
  },
  "permissions": {
    "can_post": false,
    "can_manage": true,
    "can_manage_members": true,
    "can_manage_managers": true
  }
}
```

This example is a site administrator reading a hosted members-only community
without membership. Management does not grant posting or membership.
`is_manager` means a current explicit assignment; creator status is separate.
`management_scope` is `""`, `community`, `site`, or `deployment`. Anonymous
relationship flags and mutation permissions are false. Remote replicas cannot
be managed or posted to through hosted-community mutation routes.

## Post representation

Existing fields remain: `id`, `community_id`, `object_type`, optional `title`,
`body`, `author_actor_uri`, optional `parent_id`, `authored_at`, `updated_at`, and
`deleted`. All post-producing routes, including creation, editing, and import,
add `author` and these interaction fields:

```json
{
  "author": {
    "acct": "alice@forum.example",
    "display_name": "Alice"
  },
  "like_count": 3,
  "score": 2,
  "upvotes": 3,
  "downvotes": 1,
  "voted_by_me": 1,
  "liked_by_me": true,
  "saved_by_me": false,
  "read_by_me": true,
  "hidden_by_me": false,
  "reply_count": 2,
  "permissions": {
    "can_edit": false,
    "can_delete": false,
    "can_like": true,
    "can_vote": true,
    "can_upvote": true,
    "can_downvote": true,
    "can_reply": true,
    "can_hide": false,
    "can_save": true,
    "can_hide_for_me": true,
    "can_moderate": false
  }
}
```

`author_actor_uri` remains the authoritative identity. `author.acct` is a
verified local or remote `username@domain` handle without a leading `@`, or an
empty string when unknown; it is never derived from an Actor URI path.
`author.display_name` is the stored ActivityPub `name` value, or an empty string
when unset. Browser reads use stored data only and never perform a synchronous
Actor or WebFinger lookup. Remote handles are resolved asynchronously after the
site first receives content from that author.

`score`, `upvotes`, and `downvotes` describe known active votes at this site and
are not complete federation-wide totals. `like_count` remains an alias for
active upvotes. `voted_by_me` is `-1`, `0`, or `1`; personal booleans are false
anonymously. Directions disabled by site settings are excluded from all
aggregates, personal vote state, and `can_upvote`/`can_downvote`.
`reply_count` counts visible direct replies at this site, excluding nested,
unreceived, hidden, deleted, removed, rejected, and personally blocked replies.
Lists and detail use the same metadata projection.

`can_hide` represents site/deployment moderation; `can_moderate` represents
community moderation. Authors can edit/delete only where the current local
mutation route authorizes them. Tombstones do not offer edit, like or reply.
Clients can refresh state with GET after existing like/undo mutations (204).
Permissions are UI hints: every mutation rechecks current authorization and CSRF.

## Threaded replies

`GET /api/v1/posts/{id}/replies` uses one recursive query and one response
shape. Root `items` remain the direct replies to the addressed post. Every item
contains recursive `children`, integer `depth` starting at `1`, and integer
`child_count` for its visible direct children.

```json
{
  "items": [
    {
      "id": "reply-1",
      "depth": 1,
      "child_count": 1,
      "children": [
        {
          "id": "reply-2",
          "depth": 2,
          "child_count": 0,
          "children": []
        }
      ]
    }
  ],
  "limit": 20,
  "offset": 0
}
```

`limit` and `offset` paginate only root replies. Descendants are included up to
`max_depth`, an integer from `1` through `8` with default `6`. Invalid depth,
sort, or view values return `400`. `view` accepts `tree` or the deprecated
`flat`; absent, `view=tree`, and `view=flat` all use this same query and shape.
`view=flat` only forces `max_depth=1`, so root items have empty `children`
arrays.

Replies default to `sort=old` and accept `new`, `old`, `top`, and
`controversial`. Each sibling group is sorted independently. Authored time and
ID are deterministic tie-breakers. A reply filtered out by reception, current
read permission, deletion, site hiding, personal hiding, personal blocking, or
community inclusion is omitted together with its descendants. Directly
requesting an excluded reply returns `404` without returning its body or parent
chain.

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

Mutations require a current-site session, same-origin validation, and CSRF.
Set/clear operations are idempotent and affect only the caller's row at the
resolved site. Saving, reading, or hiding an unreceived, deleted, site-hidden,
removed, rejected, or unreadable post returns `404` and creates no state.

Feeds omit posts that the caller hid for themselves. Direct post detail may
still return such a post with `hidden_by_me: true`. `/account/hidden` lists
those explicit personal hides. `/account/liked` contains only active upvotes,
not downvotes. All four listings recheck current read access and community
membership before pagination, so revoked access omits the post without leaking
its title, body, author, or counts.

The saved list orders by save time descending then post ID. Read and hidden
lists use their own state time descending then post ID. The liked list uses vote
time descending then post ID. Exhausted pages remain a successful empty page;
malformed pagination returns `400`. These states are separate from
`site_posts.hidden_at`, which remains a site-administrator action.

## Management rosters

Roster GET needs a session but no CSRF token. Existing POST/DELETE on the same
paths still require origin and CSRF validation. Both rosters sort by actor URI
ascending and support the common page parameters. Rows expose only actor identity
and flags, without account email, credentials or session data:

```json
{
  "items": [
    {
      "actor_uri": "https://forum.example/users/alice",
      "is_creator": true,
      "is_manager": false
    }
  ],
  "limit": 20,
  "offset": 0
}
```

Members contain active memberships, with both roster flags false. Managers
contain the creator plus active assignments, deduplicated by actor URI; an
assigned creator has both flags true. Site/deployment administrators are not
automatically roster entries. Revoked memberships/assignments disappear on the
next request. Remote roster proxying is not provided.

## Editing values

```json
{
  "id": "post-id",
  "title": "<b>Title &amp;</b>",
  "body": "<p>hello &amp; world</p>",
  "updated_at": "2026-10-20T00:00:00Z",
  "version": 1,
  "content_format": "legacy",
  "attachment_ids": []
}
```

Source returns stored values before display processing, including the title;
untitled replies return `title: ""`. Set editor values from these fields. Never
insert source as trusted HTML. Display GET continues to sanitize/escape content.
Source does not restore whitespace already normalized by publication/editing.
`updated_at` remains informational. Administration alone cannot read another
author's editing source. Revoked read access also revokes historical authors'
source access. Deleted bodies are unavailable.

PATCH now requires `expected_version` from the source snapshot:

```json
{
  "title": "<b>Title &amp;</b>",
  "body": "<p>updated</p>",
  "expected_version": 1
}
```

This is a breaking request-contract change: missing, null, non-positive,
fractional, string, and out-of-range values return 400. Versions are positive
signed 64-bit JSON integers; clients must retain them exactly without floating
point rounding. `If-Match` and timestamps do not replace `expected_version`.
Omitted attachment IDs retain existing bindings; an explicit empty array removes
them. Source content, attachments and version share one database snapshot.

The backend checks the version atomically with the save. Success returns 200
with the saved browser post and its incremented `version` (the example advances
to 2); publication and import responses also expose `version`. Every accepted
save, including unchanged content, advances once. Content changes from other
accepted writers invalidate drafts; likes and replies do not.

A stale save returns HTTP 409 with `Cache-Control: no-store` and:

```json
{"error":"edit_conflict"}
```

Rejected saves leave content, version, attachments, mentions, and outgoing Update
activities unchanged. Current authentication, CSRF, visibility, authorship and
deletion rules still apply before conflict disclosure. Preserve the unsaved
draft and request fresh source for comparison or manual merging. Never fetch a
new version and automatically retry the old draft against it.

Coordinate client deployment with migration 013 and revision-aware servers;
mixed old/new content writers are unsupported. Rollback requires pausing author
writes and retaining revision values. See `post-edit-concurrency-verification.md`
for writer coverage and validation evidence.

## Errors and validation

Errors use `{ "error": "message" }`. Missing/unreceived/hidden/unreadable
resources return 404. Roster/source requests without a valid session return 401;
readable resources without management/authorship authority return 403. Deleted
source returns 404. Invalid pagination returns 400. Unsupported methods on new
read paths return 405 with `Allow`; collection and roster paths retain their
existing mutation methods. Storage failures return 503 rather than empty results
or anonymous privileges. Invalid sessions on optional public reads act anonymously.

Executable acceptance coverage lives in `internal/server/browser_test.mygo` and
`internal/storage/browser_test.mygo`; use `make test-postgres` for real PostgreSQL
coverage. Public registration, search, notifications, profile editing and uploads
remain outside this contract.

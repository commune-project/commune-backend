# Forum core frontend contract

This note covers the additive HTTP contract consumed by the Elm frontend. The
backend change does not modify the frontend repository.

## Existing DTOs

Existing Elm decoders can continue to ignore unknown fields. When the client
adds support, post objects gain:

- `score`, `upvotes`, `downvotes`, `voted_by_me`
- `saved_by_me`, `read_by_me`, `hidden_by_me`
- nested reply `children`, `depth`, `child_count`
- `permissions.can_vote`, `can_upvote`, `can_downvote`, `can_save`,
  `can_hide_for_me`

`like_count` remains and equals active upvotes. `voted_by_me` is `-1`, `0`, or
`1`. Reply `items` remain root replies; decode descendants recursively from
`children`.

Community objects gain `follow_policy`, `follower_count`, and viewer fields
`is_following`, `follow_state`, and `can_follow`. Anonymous and restricted
visibility rules mean these values cannot be assumed non-zero.

Notification objects retain post notifications and add generic `target_kind`
and `target_id` for report and moderation events. Post targets use the post ID,
report-resolution targets use the report ID, and moderation targets use the
affected Actor URI. Treat these rows as display-only links and recheck current
target access through the normal read APIs.

## New actions

| Area | Endpoint | Client result |
| --- | --- | --- |
| Vote | `POST /posts/{id}/vote` | 204; refresh post metadata |
| Vote settings | `GET /site/vote-settings` | render enabled directions |
| Vote settings | `PUT /admin/vote-settings` | 200 full settings |
| Blocks | `GET/POST/DELETE /account/blocks` | refresh block list |
| Save/read/hide | `POST/DELETE /posts/{id}/save`, `POST /posts/{id}/read`, `POST/DELETE /posts/{id}/hide-for-me` | 204; refresh state |
| Account lists | `GET /account/saved`, `/read`, `/hidden`, `/liked` | paginated post page |
| Follow | `POST/DELETE /communities/{id}/follow` | 204; refresh viewer state |
| Follow review | `GET /communities/{id}/follow-requests` | management-only pending page |
| Follow decision | `POST /communities/{id}/follow-requests/{actor}` | 204; actor URI path-escaped |
| Reports | `POST /reports`, `GET /reports`, `POST /reports/{id}/resolve` | create/list/resolve |
| Modlog | `GET /modlog` | management-only append-only page |
| Bans | `POST/DELETE /communities/{id}/bans`, `/admin/bans` | 204 |
| Password reset | `POST /auth/password/reset`, `/auth/password/reset/confirm` | generic acceptance/204 |
| Password change | `POST /auth/password/change` | 204 |

All authenticated mutations require `Origin` and `X-CSRF-Token`. Preserve the
existing no-store behavior and treat `permissions` as UI hints only. Search,
feeds, notification counts, and account lists already apply blocks, hides,
community policy, deletion, reception, and inclusion before pagination.

See [api.md](api.md), [forum-browser-api.md](forum-browser-api.md),
[participation-api.md](participation-api.md), and
[permissions.md](permissions.md) for the full contracts and error mappings.

# Registration, profiles, search, notifications, and media

All browser routes select the site by the validated request authority. JSON
requests use `Content-Type: application/json`; authenticated writes require the
existing session, same-origin `Origin`, and `X-CSRF-Token`. Responses containing
viewer state or private content use `Cache-Control: no-store`. The frontend
must use the server-provided sanitized rich display, not inject editing source
as HTML.

## Email-verified registration

Registration is disabled unless the selected site's `registration_enabled` is
true. Configure SMTP, a 32-byte base64 outbox key (prefer its environment-variable
source), and participation workers as described in [configuration.md](configuration.md).

1. `POST /api/v1/auth/register` with `{"username":"alice","email":"alice@example.org"}`.
   Initial registration does not accept a password or create a public Actor.
2. The email links to `/verify-email#token=...`. That page belongs to the frontend;
   it reads the fragment and asks the email owner to choose their password.
3. `POST /api/v1/auth/verification/confirm` with `{"token":"...","password":"a-final-strong-password"}`
   consumes a valid token and creates the account and Actor together, returning
   204. It does not automatically log in. The existing login endpoint follows.
4. `POST /api/v1/auth/verification/resend` with `{"email":"alice@example.org"}`
   rotates the token, invalidating the preceding link.

Register/resend return generic 202 acceptance for valid input, including an
already registered email. Invalid bodies/tokens/passwords return 400; disabled
registration or invalid origin returns 403; rate limits return 429. The initial
password field is rejected rather than retained. Invalid final passwords do not
consume a valid token. Existing provisioned accounts remain usable. SMTP failures
after durable acceptance retry asynchronously; API acceptance does not promise
that the destination mailbox has already received the message.

## Search

`GET /api/v1/search?kind=posts&q=中文&limit=20&offset=0` searches titles and normalized
visible body text. `kind=communities` searches name/title/description. Query
matching is literal, case-insensitive substring matching, including contiguous
Chinese text; `%` and `_` are not wildcard syntax. The query must contain 1–200
Unicode code points and cannot be whitespace-only or contain NUL.

Results use `{items,limit,offset}` and existing browser DTOs. Access, reception,
hide/delete, and inclusion filters apply before pagination. Communities sort by
name then ID; posts by authored time descending then ID ascending. This endpoint
does not discover or import remote objects and does not promise relevance ranking.

## Profiles

`GET /api/v1/profiles/alice` reads the selected site's public profile.
`GET /api/v1/profile` reads the authenticated user's profile.
`PATCH /api/v1/profile` accepts any supplied editable fields:

```json
{"display_name":"Alice","biography":"A **Markdown** biography","avatar_upload_id":"uploaded-image-id"}
```

Omission preserves a field; null or an empty avatar ID removes the avatar.
Upload an image with purpose `avatar` first. An avatar and public profile are
public even when their owner participates in private communities. Credentials,
email, roles, username and Actor identity cannot be edited through this route.
Profiles federate through authoritative Person Updates; remote public avatar
URLs are not downloaded or cached by the server.

## Markdown and attachments

Upload a file with `POST /api/v1/media` as multipart form-data, with one `file`
and a `purpose` of `post` or `avatar`. Uploads require a valid session, Origin,
and CSRF token. The response supplies the upload ID, media type, byte size,
and an owner-readable reference for editor use. Include uploaded post IDs in
`attachment_ids` when publishing or editing. File ownership and binding checks
occur in the same transaction as the post mutation.

```sh
curl --fail-with-body -b cookies.txt \
  -H 'Origin: https://forum.example' -H "X-CSRF-Token: $csrf_token" \
  -F purpose=post -F 'file=@photo.png;type=image/png' \
  https://forum.example/api/v1/media
```

The 201 JSON contains `id`, `purpose`, `media_type`, `size`, `name`, `reference`,
and (for validated images) `preview_url`. Use `reference` verbatim in Markdown.

New post and reply payloads accept `content_format: "markdown"`; existing
payloads remain valid. A Markdown topic uses the existing community-topic route:

```json
{"title":"Illustrated discussion","body":"Hello @alice\n\n![Example](upload-reference)\n\n[Download](another-upload-reference)","content_format":"markdown","attachment_ids":["image-upload-id","file-upload-id"]}
```

The literal references above stand for references returned by upload, not disk
paths. Basic CommonMark formatting, code, links and inline raster images are
supported. Raw HTML cannot bypass the final HTML allowlist sanitizer. Ordinary
files, including PDF and archives, download with safe disposition; HTML/SVG are
never treated as executable inline previews. Image dimensions, upload bytes,
per-user/site quotas, and attachment counts are bounded.

Browser post output retains the existing escaped/plain `body` and adds
`body_html`, `content_format`, `attachment_ids`, and `attachments`. Each attachment
contains `url`, `media_type`, and optional `name`/`preview_url`. Editing reads the existing author-only source
route, never reconstructs Markdown from rendered HTML. Old posts retain legacy
interpretation unless explicitly edited as Markdown. Source whitespace remains
subject to existing publication normalization.

Mentions support `@alice` and `@alice@example.org`. Code, escaped markers, link
and image destinations, and email addresses do not trigger mentions. Unresolved
actors remain text. Mentioning someone grants no access and cannot export a
local-only or private discussion to an outsider.

## Notifications

- `GET /api/v1/notifications?limit=20&offset=0` lists current eligible notifications
  and a snapshot cursor, newest first.
- `GET /api/v1/notifications/unread-count` returns the current unread count.
- `POST /api/v1/notifications/{id}/read` marks one own notification read.
- `POST /api/v1/notifications/read-all` with `{"through_cursor":"..."}` marks
  eligible notifications through that snapshot read. Later arrivals stay unread.

Replies, likes, and mentions notify eligible local recipients; self-actions do
not. A reply that also mentions its parent's author yields one notification with
mention precedence. Network retries do not duplicate logical events. Undoing a
like or removing a mention retires its notification. Reads and counts recheck
current access, so revoked members no longer receive private titles or counts.

## Media operation and retention

Keep the configured media root on persistent storage outside any directly
served static directory. Back up authoritative local files with the database.
Attachment routes check the containing resource's current permissions before
original, preview, HEAD, range, or conditional responses. Knowing a URL does not
authorize a private attachment.

Remote public media remains an origin URL: no backend proxy, cache, thumbnails,
or warmup requests. Public images load from the origin in the browser with a
no-referrer policy. The origin therefore sees the reader's connection.
Remote non-public media can be fetched only through an authorized compatible
peer path. Private cache bytes expire from fetch time; reads do not renew their
retention. Periodic cleanup removes bytes while retaining metadata; the next
eligible access can refetch after authorization. Unsupported restricted peers
never fall back to an anonymous public fetch.

Removing a remote member through the browser API queues a Group-signed targeted
revocation for capable Commune peers in the mutation transaction. The control
message may reach the former member after content delivery stops; it contains
only that Actor's removal, not private posts or the remaining membership roster.

Private originals use `/api/v1/media/private/{id}`. Validated raster previews use
`/api/v1/media/private/{id}/preview`; both require the current site's session and
current containing-post access. Remote MIME declarations alone never authorize
an inline image. Preview bytes expire and are deleted with the corresponding
private cache generation. Origin requests use Actor-signed GET, bounded bytes
and time, checked DNS addresses, and same-origin redirects only.

Separate cleanup handles expired unbound uploads and unreferenced local sources.
Do not apply remote-cache retention to authoritative local uploads. Received
deletion/removal and policy changes stop the affected access path; a scoped hide
does not delete another site's legitimately shared source. Remote copies already
delivered cannot be guaranteed to disappear.

Deploy additive migrations before the new executable. Enable workers explicitly,
test SMTP and directory permissions, then enable registration per site. On
rollback disable registration/new writes and workers first, preserve new schema
and authoritative files, and check compatibility before restoring an older
binary. Disposable remote-private cache can be purged separately.

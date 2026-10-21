## Context

See proposal.md for motivation and specs/ for observable contracts. The project uses MyGO with generated Go, PostgreSQL migrations, site-selected HTTP routing, hashed sessions, and CSRF-protected writes. Accounts are currently provisioned; Person profiles contain no biography or icon. Posts share canonical identity across receiving sites. BrowserRepository already centralizes readable-community projections and batches post metadata. RenderText strips and escapes text; it is not a Markdown renderer or rich-HTML sanitizer. Federation has durable activity receipts/delivery, but protected media and profile Update processing need explicit extensions.

## Goals / Non-Goals

Goals: implement one consistent permission model across search, notifications, media, rendering, and federation; preserve editable source and existing browser DTO fields; separate authoritative files from disposable remote cache bytes; make background work restartable and bounded.

Non-goals: recover passwords, change email or username, implement the browser editor, offer arbitrary HTML embedding, cache remote public bytes, provide realtime push, transcode video, or guarantee withdrawal of copies already delivered to another server. The backend supplies image previews and safe rendered HTML for a frontend to consume.

## Decisions

### 1. Additive capability and migration boundaries

Use additive versioned migrations for pending registrations, mail jobs, profiles, post format/source metadata, media records/bindings, mentions, notification events/rows, and leases. Existing posts default to legacy text interpretation, not Markdown; explicit Markdown publication/edit enables the new format. Keep browser title/body behavior and add body_html and content_format uniformly to detail, lists, create/edit, and import. Extend the authorized source response with format and attachment references while retaining id/title/body/updated_at. Reuse current source permission checks. This avoids silently reinterpreting legacy text or breaking clients that rely on escaped body fields.

### 2. Verification before account activation

Keep pending registrations separate from accounts and actors. Initial registration accepts username and email only; reject password fields and store no pending password or password hash. Store normalized identifiers, token digest, generation, expiry, and site. Confirmation accepts token and the final password; after validating both, it locks the pending row and atomically creates the account/Actor with the freshly hashed final password, checks unique constraints, and consumes the token; it does not auto-login. Invalid passwords do not consume the token. Initial tokens expire after 24 hours; resend rotates generation and restarts expiry without accepting credentials. Duplicate valid submissions receive the same 202 response and do not overwrite the pending username. Existing provisioned accounts are explicitly grandfathered and retain existing login behavior.

Use a durable SMTP outbox rather than sending inside an HTTP/database transaction. Verification records hold only digests; the temporarily needed outbound link is stored as authenticated encrypted mail-job data using a deployment-supplied secret outside the database. Workers lease, retry transient failures with bounded backoff, discard superseded generations, and erase secret payloads on completion/expiry. SMTP delivery is at-least-once; duplicate delivery of the same link is harmless. Restrict credential disclosure to TLS-protected SMTP; local test transport uses a deliberate test setting. No actual mail is sent during tests. Use site-scoped rate-limit records keyed by trusted client IP and a digest of normalized email; trust forwarded addresses only through configured proxies. Return 429 with Retry-After. Keep username conflicts generic rather than exposing email ownership.

### 3. Local filesystem lifecycle

Use a configured absolute media root outside a directly served web directory, separate local-source, temporary-upload, preview, and remote-private-cache namespaces, and server-generated identifiers. Resolve all opens relative to the root with traversal/symlink safeguards. Stream to a restricted temporary file, enforce byte and quota reservations, validate MIME/signature, then atomically finalize metadata and file publication. Reconcile orphan files/reservations after crashes. Never use client filenames as paths. One upload binds to one post or avatar use; replacement creates a new binding rather than mutating a shared file's ownership.

Support common raster image formats with decoder-enforced pixel/dimension bounds and bounded preview generation. Treat ordinary files as downloads, including PDF and archives; never extract archives. SVG/HTML are downloadable with restrictive disposition and sandboxing headers, never inline previews. Apply nosniff to all served files. Reject malformed declared images rather than treating them as safe previews. Local-only/private files and temporary uploads are no-store. Public files can be read anonymously only while a currently valid public binding authorizes the read.

Private file URLs identify a binding, not a public disk object. Every original, preview, HEAD, range, and conditional read checks that binding's current site/resource permission before inspecting or returning file metadata. Unbinding, hiding, deleting, or changing community policy closes that access path immediately; it does not physically destroy another site's legitimate shared source. Cleanup deletes expired unbound uploads and unreferenced local sources separately from remote cache. Do not promise local-source deletion merely because a receiving site hides a shared post.

Initial configurable defaults: 25 MiB per ordinary file, 10 MiB per image, 20 megapixels, 1 GiB per account, 10 GiB per site, 24-hour temporary-upload retention, 7-day private-cache retention, hourly cleanup. Validate all settings; document these defaults as operational choices rather than fixed protocol limits. Reserve bytes transactionally so concurrent uploads cannot evade quotas; actual disk exhaustion fails without exposing partial files.

### 4. Remote media classification and protected fetching

Classify by the authoritative containing content's verified audience and community boundary; an anonymously retrievable URL does not prove public content. Remote public media and public avatars are metadata plus external URLs only. No backend GET/HEAD, preview generation, proxy endpoint, cache warmup, or opportunistic import download is permitted for this class. Rendering uses the origin URL and no-referrer policy. This intentionally exposes readers' network addresses to the origin; do not silently introduce a proxy to change it.

For remote private media, on-demand fetching uses the requesting member's Actor identity and the existing protected-federation authorization model. The origin verifies the signed Actor and its current access to the owning post. The receiver rechecks its own site reception, current reader membership, blocks, resource state, and peer compatibility on every hit and miss. A server signature alone conveys no membership. Fetch through the controlled federation network client with DNS/address validation on every hop, byte/time/redirect bounds, and no anonymous fallback; avoid forwarding credentials across origin redirects. Peers lacking this path are incompatible for restricted media. Do not claim general Mastodon private-media interoperability from local-cache behavior alone.

Cache keys include origin media identity/version and the protected resource/access scope. Bytes live only under a private root; retain fetched_at, expires_at, file state, lease generation, size, and error state separately from permanent attachment metadata. Expiry is based on successful fetch, never extended by reads. Reject expired entries even before the cleaner runs. A leased cleaner marks entries deleting and coordinates with open/fetch leases before unlinking; a failed unlink retries. Refetch requires current local authorization and successful origin authorization. Origin denial, scope reclassification, object deletion, or authoritative attachment removal invalidates the matching cache generation; one reader's membership loss denies that reader without destroying valid access for others. Periodic jobs never prefetch expired entries. Retention and capacity eviction affect only bytes, not source metadata or local authoritative files.

### 5. Markdown and HTML are different inputs

Introduce an explicit content-format model. Use a maintained AST Markdown parser with raw HTML disabled and an independent HTML parser-based allowlist sanitizer for rendered local Markdown and received remote HTML. Choose exact dependency versions after checking current Go/MyGO FFI compatibility during implementation; do not build security filtering from regex. Permit the documented basic Markdown subset, safe anchors, raster images, and generated mention links; remove executable elements, event/style attributes, embedded frames, and unsafe schemes including encoded forms. Sanitize final output after URL/mention expansion. Link/image rendering must not cause server-side external media fetches. Use no-referrer for external images and safe link relationships. Store source independently from generated display; never derive editing source by reversing sanitized HTML.

Emit federation content as safe HTML with mediaType text/html and optional source {content,mediaType:text/markdown} for local Markdown objects. Existing access boundaries govern the whole representation; source metadata does not make an otherwise protected object public. Treat remote optional source as author data, not trusted display HTML. Profile biographies share the renderer/sanitizer but do not trigger post mention notifications.

### 6. Resolve mentions from structured text

Walk Markdown AST text positions outside code, escaped markers, existing links/images, and email text. Resolve @username within the current site and @username@domain through existing controlled Actor discovery. Bound mention count, total discovery work, input lengths, and remote fetch time; unresolved/blocked identities remain literal text. Store canonical Actor URI and a stable source span separately from visible spelling. Bind local media references to validated owned uploads; reject foreign/unbound private IDs instead of emitting their URLs.

Mentions neither grant membership nor change audience. Eligible remote recipients are added only within the permitted federated audience; local-only content never causes remote delivery. Received mention tags must match a verified post and an addressed, permitted local recipient before notification. Actor URI, not a display string, is the deduplication key. During edits diff previous active mentions: unchanged mentions do not renotify, removals retire notifications, and later reintroduction creates a new occurrence. If a reply both replies to and mentions one user, keep one visible notification with mention precedence.

### 7. Durable notifications and search reuse read projections

Record notification events in the same transaction as committed local changes and accepted remote state changes. A leased projector derives eligible local recipients and upserts unique logical event/kind/recipient rows. Event identity includes the relevant action occurrence so Undo then re-like is distinct while network replay is not. Projector retries are idempotent. List/count queries independently recheck current access and retirement state before pagination/aggregation, so policy changes do not rely on prompt background cleanup. Use one timestamp/ID upper-bound cursor for mark-all; notifications arriving after that snapshot stay unread.

Use PostgreSQL literal substring search with escaped ILIKE expressions, binding all user values. This provides contiguous Chinese matching without introducing a tokenizer service. Search normalized text stripped of markup rather than generated HTML; update it alongside authoritative source/body changes. Reuse site-scoped readable-community/post predicates before limit/offset; retain administrative audits and unavailable error mapping. Sort communities by name/ID and posts by authored_at descending/ID ascending, rather than promising language-specific relevance. Run representative query plans before deciding whether an optional trigram extension/index is justified; initial correctness does not depend on an uninstalled extension.

### 8. API surface and error mapping

| Route | Method and contract |
| --- | --- |
| /api/v1/auth/register | POST username/email only; same-origin; 202 generic acceptance |
| /api/v1/auth/verification/resend | POST email; same-origin; 202 generic acceptance |
| /api/v1/auth/verification/confirm | POST token/password; same-origin; 204 success; no session issuance |
| /api/v1/search | GET kind=communities or posts, q, limit, offset; existing page envelope |
| /api/v1/profiles/{site-local-username} | GET public local profile |
| /api/v1/profile | GET/PATCH current profile; writes use CSRF |
| /api/v1/media | POST multipart file and purpose; returns id/type/size/reference |
| /api/v1/media/{binding-id} | GET/HEAD original; authorized single-byte-range support |
| /api/v1/media/{binding-id}/preview | GET/HEAD validated raster preview |
| /api/v1/notifications | GET bounded list plus snapshot cursor |
| /api/v1/notifications/unread-count | GET current eligible unread count |
| /api/v1/notifications/{id}/read | POST idempotent read mutation |
| /api/v1/notifications/read-all | POST through_cursor; bounded snapshot read mutation |

Expose attachment_ids and content_format as optional fields on existing post publish/edit payloads; absent format on new posts remains legacy-compatible, while editing preserves the stored format unless explicitly changed. Profile PATCH accepts display_name, biography, avatar_upload_id including explicit removal. Media upload responses use a stable owner-preview reference before binding; post rendering rewrites validated upload references into resource-bound routes. A binding URL never becomes an independently public bearer credential.

Validate unknown fields and body limits consistently; JSON routes retain strict decoding while multipart uses its own streaming limit. Return 400 invalid input/token/cursor, 401 missing session, 403 denied public operation or forbidden owner action, 404 missing/inaccessible resource, 405 with Allow for unsupported methods, 409 binding/uniqueness conflict where disclosure is safe, 413 excessive upload bytes, 415 unsupported upload encoding, 429 rate/quota limits with documented machine-readable reason, and 503 required storage/mail-queue/filesystem unavailability. SMTP retry after a durably queued 202 is asynchronous. All identity-, search-, source-, and notification-dependent reads are no-store. Public profile output excludes email/account secrets.

### 9. Federation validation scope

Extend Person discovery/Update handling, object parsing/representations, and durable delivery using icon, summary, attachment, tag/Mention, source, and recipients without rewriting canonical identity or signed forwarded payloads. Reject forged or stale profile/object updates using authoritative freshness handling. Coordinate profile/avatar and post attachment mutation with durable outgoing events. Test two independent Commune processes, including restricted media access, cache expiry/refetch, revocation, and local-only exclusion. For Lemmy, Mastodon, and Misskey pin peer versions and run the public profile/attachment/mention matrix; record field-specific limitations and separate fixtures from live results. Existing restricted-peer gates remain in force.

## Risks / Trade-offs

- [Remote public images contact the origin from the reader's browser] → no-referrer; expose remote origin metadata to clients; preserve the explicit no-proxy/no-cache decision.
- [Previously delivered remote files cannot be recalled] → enforce future reads and propagation boundaries; make no remote-deletion guarantee.
- [Filesystem/database updates cannot share a transaction] → temporary files, atomic rename, durable state transitions, leases, and orphan reconciliation tests.
- [Private cache outlives a user's authorization] → check every request; do not use possession of bytes as authority; bounded expiry and origin-authorized refetch.
- [Registration and remote mentions create abuse/cost] → per-site limits, SMTP retry bounds, quotas, bounded remote discovery, and default-disabled registration.
- [Substring search scans grow] → bounded queries, shared access predicates, representative plans, and evidence-driven indexes without changing search semantics.
- [Sanitizer or parser mistakes expose XSS] → independent parser-based sanitization, adversarial local/remote fixtures, and exact dependency versions recorded in implementation evidence.

## Migration Plan

1. Add schema and validation tests; deploy additive migrations and configured persistent media paths. Existing accounts and legacy posts remain valid.
2. Deploy with registration disabled; verify SMTP test transport, outbox secret configuration, media permission probes, worker leases, cleanup dry-run reporting, and disk quota settings.
3. Enable features per configured site, validate two-instance federation and supported public peer profiles, then enable public registration after an operator verifies actual mail delivery.
4. Roll back by disabling registration/new writes and workers and restoring the previous executable only after checking migration compatibility. Do not drop new columns/tables or media directories during rollback; back up database and authoritative local media together. Disposable remote-private cache may be purged separately.

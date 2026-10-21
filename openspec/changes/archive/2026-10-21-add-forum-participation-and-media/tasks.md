## 1. Schema, configuration, and compatibility

Implementation checks and per-task evidence are recorded in
[`docs/participation-verification.md`](../../../../docs/participation-verification.md).
Process-level acceptance remains separate from repository and HTTP tests.

- [x] 1.1 Add registration, SMTP/outbox-secret, media-root/quota/retention, rendering, and worker configuration with documented defaults; verify invalid paths, bounds, missing enabled-feature secrets, and existing configuration compatibility.
- [x] 1.2 Add pending-registration, verification-generation, mail-outbox, and rate-limit migrations; verify upgrade from the existing schema, site-unique identifiers, concurrent redemption constraints, and unchanged provisioned-account login in PostgreSQL.
- [x] 1.3 Add profiles, post format/source/search-text, media/binding/cache/lease, and mention migrations; verify legacy text defaults, stable shared identities, site/owner constraints, and existing post reads.
- [x] 1.4 Add durable notification-event and recipient/read-state tables with occurrence uniqueness; verify duplicate inserts converge and distinct re-like/re-mention occurrences remain distinct.

## 2. Verified public registration

- [x] 2.1 Implement username/email-only pending registration and site-scoped IP/email rate limits; verify rejection of password fields, disabled registration, invalid inputs, generic existing-email responses, trusted-proxy handling, 429, and no pre-verification Actor/session/role or stored credentials.
- [x] 2.2 Implement token issuance, resend rotation, expiry, and token-plus-final-password atomic confirmation/account creation; verify email-owner password selection after third-party initiation, invalid passwords do not consume tokens, concurrent redemption, cross-site replay, stale tokens, uniqueness races, and unchanged existing credentials.
- [x] 2.3 Implement encrypted durable mail jobs and bounded SMTP delivery leases/retries; verify restart recovery, stale-generation suppression, payload erasure, TLS policy, no secret logging, and fake-SMTP delivery without contacting real recipients.
- [x] 2.4 Add register/resend/confirm HTTP routes and documentation; verify same-origin, strict JSON/body bounds, 202/204/error contracts, no-store, and successful verification followed by normal login.

## 3. Authoritative local media

- [x] 3.1 Implement root-confined streaming file storage, quota reservation, atomic finalize, and orphan reconciliation; verify traversal/symlink attempts, concurrent quotas, cancellation, disk errors, and crash-stage cleanup using temporary directories.
- [x] 3.2 Add upload routing and metadata/owner-preview responses; verify current-site session, Origin/CSRF, multipart bounds, purpose/MIME validation, safe filenames, and rejection of cross-owner use.
- [x] 3.3 Add bounded raster decoding/previews and safe ordinary-file download headers; verify valid images, malformed/decompression-heavy images, PDF/archive downloads, and non-executable HTML/SVG handling.
- [x] 3.4 Implement transactional post/avatar binding and resource-authorized original/preview/HEAD/range/conditional reads; verify revoked membership, hidden/deleted/unreceived posts, policy changes, unbinding, and unrelated-site isolation without harming other legitimate shared bindings.
- [x] 3.5 Add leased cleanup for expired unbound uploads and unreferenced local sources; verify idempotency, in-flight transfer coordination, failed-unlink retries, and retention of bound authoritative files.

## 4. Markdown, source, and mentions

- [x] 4.1 Select and pin maintained Markdown AST and independent HTML allowlist dependencies after checking official APIs and current MyGO FFI support; verify generated compilation and record versions and the allowed Markdown/HTML subset.
- [x] 4.2 Implement explicit legacy/Markdown/remote-HTML interpretation, source preservation, and final sanitization; verify markup/entity round trips, legacy compatibility, remote HTML handling, and adversarial encoded/malformed XSS fixtures.
- [x] 4.3 Add validated upload references and body_html/content_format across every browser post response path; verify inline previews/download links, stored source retrieval, create/edit/import consistency, and denial of foreign/private reference reuse.
- [x] 4.4 Implement AST-based local/remote mention resolution and canonical metadata; verify code/link/image/email/escape exclusions, bounded discovery, blocked/unresolved actors, URI deduplication, and no remote lookup caused by image rendering.
- [x] 4.5 Implement mention occurrence diffs and audience filtering during post mutations; verify unchanged edits, removal/reintroduction, outsider mentions, local-only exclusion, and transactional rollback of bindings/mentions on failed publication.

## 5. Profiles and profile federation

- [x] 5.1 Add public/current profile GET and owner PATCH with avatar binding/removal; verify field bounds, sanitization, CSRF, disabled accounts, immutable identity/private fields, and public avatar policy.
- [x] 5.2 Extend Person discovery/representations and authoritative Actor Update processing/delivery; verify forged/stale updates, unchanged Actor identity, blocked actors, avatar replacement propagation, and zero media GET/HEAD/cache files for public remote avatars.

## 6. Rich-content federation and private cache

- [x] 6.1 Extend post federation parsing/output for HTML/mediaType/source, attachments, Mention tags, and authorized recipients; verify bidirectional Create/Update reconciliation, deleted-object replay, optional-field tolerance, and intact inner-activity forwarding.
- [x] 6.2 Add protected attachment origin routing using verified requesting-Actor identity and current containing-post access; verify signed non-members/server-only signatures fail, members succeed, local-only resources never export, and unsupported restricted peers remain denied.
- [x] 6.3 Implement remote audience-based media classification and direct public-source rendering; verify imports, profile updates, Markdown rendering, and display create no backend public-media request, proxy, preview file, or cache job.
- [x] 6.4 Implement authorized on-demand private-media fetch/cache with generation/transfer leases; verify scoped keys, current reader checks on hits/misses, controlled DNS/redirect/byte/time handling, origin denial, and no anonymous fallback.
- [x] 6.5 Add configurable finite cache expiry and periodic deletion preserving metadata; verify reads do not renew expiry, expired bytes are unservable before cleanup, unlink races/restarts are safe, and authorized misses refetch while revoked users cannot.
- [x] 6.6 Handle attachment removal, public/private reclassification, deletion, and received revocation without deleting authoritative local files; verify matching cache generations invalidate and one user's revocation does not corrupt another user's valid binding.

## 7. Notifications

- [x] 7.1 Emit durable notification events from committed local reply/like/mention operations and verified remote acceptance; verify failed actions emit nothing, network replay/worker retries deduplicate, and self/ineligible/cross-site recipients receive nothing.
- [x] 7.2 Implement recipient projection, reply/mention precedence, occurrence lifecycle, and retirement; verify Undo/re-like, mention removal/reintroduction, author deletion, and one visible notification for a reply that mentions its parent author.
- [x] 7.3 Add notification list/unread-count/single-read/snapshot-read-all routes; verify current visibility before pagination/counting, revocation and block privacy, stable ordering, cross-account access denial, CSRF, no-store, and concurrent arrival after mark-all cursor.

## 8. Search

- [x] 8.1 Maintain normalized searchable text and implement literal case-insensitive Chinese-capable community/post search using shared read predicates; verify punctuation escaping, remote HTML/Markdown text, updates, tombstones, site reception, and authorization filtering before offsets.
- [x] 8.2 Add search HTTP routing and enriched response pages; verify kind/query/length/page validation, deterministic ties, empty arrays, administrative audit, unavailable storage errors, and no remote fetches.
- [x] 8.3 Record representative PostgreSQL search and notification query plans and page-size enrichment counts; add versioned indexes only where evidence justifies them and verify no required unavailable extension is introduced.

## 9. Runtime, documentation, and acceptance

External peer acceptance (9.5) is temporarily deferred by the user's explicit
instruction on 2026-10-20. Keep this task unchecked; local tests do not establish
Lemmy, Mastodon, or Misskey interoperability.

Archive authorized by the user on 2026-10-21 after completion of 9.3 and 9.4.
Implementation commit: `c8ecb0a`. Task 9.5 remains explicitly deferred and
unchecked; archival does not claim external-peer acceptance.

- [x] 9.1 Integrate bounded mail, notification, media-cleanup, and reconciliation workers with graceful shutdown; verify lease recovery, retry limits, multiple-worker exclusion, and cleanup-only operation that never prefetches remote media.
- [x] 9.2 Publish API JSON/multipart/Markdown examples and configuration, SMTP, backup, cache-cleanup, and rollback instructions; verify examples against HTTP tests and explicitly distinguish authoritative files from disposable private cache.
- [x] 9.3 Run a real PostgreSQL multi-site acceptance matrix across registration, profile/media edits, search, notifications, revocation, audits, and retained mutation behavior; record exact commands and results for all seven capability contracts.
- [x] 9.4 Run two independent Commune deployments through profile updates, attachments, Markdown, mentions, private fetch/expiry/refetch/revocation, and local-only exclusions; record versioned process-level evidence rather than substituting fixtures for live exchange.
- [ ] 9.5 Pin Lemmy, Mastodon, and Misskey versions and run public profile/attachment/mention compatibility scenarios; record live outcomes and field-specific limitations separately from fixture and unsupported restricted-media results.
- [x] 9.6 Regenerate Go through the existing Makefile package order, run bounded make build/test/test-postgres and relevant federation suites with writable task-local caches, and verify no generated file was edited manually.
- [x] 9.7 Run openspec validate add-forum-participation-and-media --strict, review implementation/API/spec consistency, and map each completed task to evidence before proposing sync/archive.

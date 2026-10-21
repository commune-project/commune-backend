## Why

The forum can now be browsed and managed, but ordinary users still cannot register publicly, search discussions, receive notifications, maintain profiles, or publish illustrated discussions and attachments. These capabilities must work across federation without weakening current site, community, authorship, or sanitization boundaries.

## What Changes

- Add site-configurable public registration with SMTP email verification, expiring single-use tokens, resend controls, and activation before login.
- Add site-scoped Chinese-capable search of readable communities and posts.
- Add durable reply, like, and mention notifications with unread counts and read controls.
- Add editable display names, biographies, and uploaded avatars while preserving account and Actor identity.
- Add Markdown source, sanitized rendered HTML, inline attachment references, and local/remote mentions without changing existing plain display fields.
- Store uploads in a configured local directory; support image previews and ordinary-file downloads with ownership, quota, and resource-access checks.
- Support profile, attachment, rich-content, and mention federation. Never cache or proxy remote public media; allow authorized remote non-public media caching with configurable periodic deletion and authorization on every read/refetch.

## Capabilities

### New Capabilities

- `public-registration`: Site-scoped email-verified registration and reliable verification delivery.
- `forum-search`: Access-filtered, Chinese-capable community and post search.
- `user-notifications`: Durable reply, like, and mention notifications and read state.
- `user-profiles`: Public profile reads, owner edits, avatars, and authoritative profile federation.
- `rich-post-content`: Markdown rendering, HTML sanitization, source preservation, and mention resolution.
- `forum-media`: Local uploads, binding, previews/downloads, remote media handling, and cleanup.
- `rich-content-federation`: Bidirectional rich posts, attachments, mentions, and protected-media interoperability.

### Modified Capabilities

None. These additive contracts retain existing browser fields, source authorization, shared-object identity, site isolation, and current federation restrictions.

## Impact

Changes will affect MyGO configuration, migrations, account/session checks, storage repositories, browser routing, content rendering, federation parsing/representations/delivery, and runtime workers. New dependencies are expected for Markdown parsing and allowlist HTML sanitization; SMTP and filesystem facilities can use Go standard-library FFI. Deployment needs SMTP settings, a persistent writable media directory, disk quotas, and cleanup scheduling. Documentation, generated Go, PostgreSQL acceptance tests, and versioned federation evidence must be updated. Password recovery, email changes, browser push/WebSocket delivery, external search services, S3 storage, and frontend implementation are outside this change.

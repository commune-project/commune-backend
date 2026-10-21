## Purpose

Provide editable public-facing profile information and avatars while preserving stable account identities and authoritative federation ownership.

## ADDED Requirements

### Requirement: Owner-edited public profiles
Users SHALL be able to read public profiles and edit their own display name, biography, and avatar using current-site sessions, same-origin checks, and CSRF. Fields SHALL have configured bounded lengths and sanitized display output. Avatars SHALL use validated owned image uploads and support removal. Username, Actor URI, email, credentials, and roles SHALL NOT be editable through this endpoint or exposed as private profile data. Public profiles and avatars SHALL be explicitly public irrespective of the visibility of posts their owners author. Disabled local accounts SHALL NOT accept edits.

#### Scenario: Avatar replacement
- **WHEN** an authenticated owner replaces an avatar with an owned valid image
- **THEN** subsequent profile reads show the replacement and another account cannot reuse the upload as its own avatar

### Requirement: Authoritative profile federation
Person representations SHALL include current display name, sanitized biography, and avatar metadata. Local profile changes SHALL issue authoritative Actor Update delivery to eligible followers. Remote profile changes SHALL require verified ownership of the unchanged Actor identity and SHALL respect freshness and block rules. Remote public avatars SHALL retain source URLs without server-side download, proxying, or caching. A remote update SHALL NOT alter local accounts or install executable profile markup.

#### Scenario: Forged or stale Actor update
- **WHEN** a sender attempts to update another Actor or an older profile update follows a newer one
- **THEN** the current authoritative profile remains unchanged

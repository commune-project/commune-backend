## MODIFIED Requirements

### Requirement: Authoritative profile federation
Person representations SHALL include current display name, sanitized biography, and avatar metadata. Local profile changes SHALL issue authoritative Actor Update delivery to eligible followers. Remote profile changes SHALL require verified ownership of the unchanged Actor identity and SHALL respect freshness and block rules. A blank remote display name MAY be bootstrapped once from the canonical public Actor document's ActivityPub `name` after the document's identity is required to match the stored Actor URI; this bootstrap SHALL NOT overwrite a non-empty display name, SHALL NOT alter local profiles, SHALL NOT install executable markup, and SHALL NOT outrank a later verified Person update. Remote public avatars SHALL retain source URLs without server-side download, proxying, or caching. A remote update SHALL NOT alter local accounts or install executable profile markup.

#### Scenario: Forged or stale Actor update
- **WHEN** a sender attempts to update another Actor or an older profile update follows a newer one
- **THEN** the current authoritative profile remains unchanged

#### Scenario: Blank remote display name bootstrap
- **WHEN** a canonical public Actor document matching the stored Actor URI supplies a non-empty `name` and the remote profile has no display name
- **THEN** the blank display name is populated as sanitized plain text without fetching avatar bytes

#### Scenario: Bootstrap cannot overwrite authoritative data
- **WHEN** a remote profile already has a non-empty display name or is a local profile
- **THEN** public-document bootstrap leaves the existing display name unchanged

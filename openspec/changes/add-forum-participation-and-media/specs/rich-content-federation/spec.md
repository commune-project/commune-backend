## Purpose

Exchange rich discussion content, attachments, and mentions bidirectionally while preserving object ownership and restricted-audience boundaries.

## ADDED Requirements

### Requirement: Bidirectional rich object representation
Federated post Create and Update SHALL carry sanitized HTML content, declared media type, structured attachments, canonical mention tags, and appropriate mention recipients within the permitted audience. Local Markdown source SHALL be available in source metadata only where the existing object access boundary permits it. Remote representations with HTML, optional source, attachment, or mention fields SHALL preserve canonical object identity and author authority; source SHALL NOT be trusted as executable display content. Authored updates SHALL reconcile attachments and mentions without resurrecting deleted content. Unknown optional fields SHALL remain tolerated and intact forwarding SHALL preserve signed inner activities.

#### Scenario: Remote post update replaces attachments
- **WHEN** an authorized remote author updates an accepted post with a new attachment and removes an old mention
- **THEN** the current display and bindings reflect the update, retired notifications are suppressed, and shared identity remains unchanged

### Requirement: Protected media interoperability gates
Protected attachment retrieval SHALL authenticate the requesting Actor and authorize current access to the containing resource. Receiving servers SHALL NOT obtain protected bytes solely by identifying themselves as a server or possessing an attachment URL. Local-only media SHALL never be exported. Unsupported external peers SHALL receive no restricted attachments or audience expansion; their public rich-content compatibility SHALL be reported independently. Two independent Commune deployments SHALL demonstrate authorized private-media fetch, expiry, refetch, and revocation. Lemmy, Mastodon, and Misskey public profiles SHALL record exact tested versions, rich-content outcomes, and limitations; fixture tests SHALL NOT be claimed as live interoperability.

#### Scenario: Signed non-member fetch
- **WHEN** an otherwise valid signed request from a non-member requests a protected attachment
- **THEN** access is denied and neither origin nor cache reveals protected bytes

#### Scenario: Public-compatible peer lacks private-media support
- **WHEN** a peer supports public attachments but cannot satisfy protected Actor authorization
- **THEN** public interactions remain supported and restricted media delivery remains denied

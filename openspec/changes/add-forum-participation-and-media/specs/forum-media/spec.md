## Purpose

Support local image and document uploads and authorized remote media access with distinct source-file and temporary-cache lifecycles.

## ADDED Requirements

### Requirement: Owned bounded local uploads
Authenticated users SHALL be able to upload images and ordinary files into a configured persistent local directory with same-origin and CSRF checks. Uploads SHALL enforce configured per-file, per-user, and per-site limits while streaming, inspect actual file type, and use server-generated storage paths confined to the configured root. Original names SHALL be display metadata only. Upload responses SHALL provide an ID, media type, size, and Markdown-usable reference. Unbound uploads SHALL be owner-readable only and expire after a configured interval. Binding SHALL validate site, owner, intended use, and current publishing/editing authority atomically; concurrent requests SHALL NOT bypass quotas or reuse another owner's upload.

#### Scenario: Malicious filename and oversize upload
- **WHEN** an upload supplies traversal components or exceeds configured size or quota
- **THEN** it cannot write outside the media root or leave a readable partial upload and receives a bounded error

### Requirement: Permission-aware preview and download
Supported decoded raster images SHALL have bounded-dimension previews suitable for Markdown image display. Other supported files, including PDF and archives, SHALL be downloadable with safe disposition and MIME handling; HTML and SVG SHALL NOT execute inline. Local-only and private attachments SHALL inherit current resource access, site reception, hide/delete/inclusion state, and membership checks on every read, including conditional and range requests. Unbinding or deleting a post SHALL make its attachments unavailable through that binding. Scope-specific hiding SHALL NOT delete another authorized site's shared source file. Avatar source files SHALL follow explicit public-profile rules.

#### Scenario: Revoked member knows the file URL
- **WHEN** a former member requests a private attachment through its original, preview, range, or conditional URL
- **THEN** the request reveals neither file bytes nor restricted file metadata

### Requirement: Remote public media remains uncached
Remote media classified as public from its containing content's verified audience SHALL retain origin metadata and URL only. The server SHALL NOT download, proxy, persist, thumbnail, or warm-cache those bytes, including public avatars and Markdown images. Browser image previews SHALL reference the remote source with a no-referrer policy. Classification SHALL NOT rely solely on a URL being anonymously retrievable. If previously cached private media becomes public, stale cached bytes SHALL cease being served and become eligible for deletion.

#### Scenario: Public remote illustration
- **WHEN** a public remote post containing an image is imported and displayed
- **THEN** its preview references the remote URL and no media fetch job or local media file is created

### Requirement: Expiring authorized private-media cache
Non-public remote media SHALL be fetched only for a currently authorized request through a compatible authenticated peer path and controlled network requests with byte, redirect, timeout, and address restrictions. Cached bytes SHALL remain private and SHALL NOT bypass per-reader checks. Cache files SHALL have a configurable finite retention period from successful fetch, SHALL NOT extend retention merely through reads, and SHALL be periodically deleted with crash-safe coordination against active transfers. Metadata SHALL survive expiry. A cache miss SHALL refetch only after rechecking current authorization and origin policy; failed authorization or unsupported peers SHALL NOT trigger anonymous fallback. Cleanup SHALL distinguish private remote cache files, unbound uploads, and authoritative local sources.

#### Scenario: Cache expiry and later access
- **WHEN** a cached private file expires and an authorized user later opens it
- **THEN** periodic cleanup can delete its bytes without deleting metadata and access can refetch through the authorized origin path

#### Scenario: Authorization lost before refetch
- **WHEN** an expired private file is requested after membership or origin authorization is revoked
- **THEN** neither cached bytes nor an unauthorized refetch is provided

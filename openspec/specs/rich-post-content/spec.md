# rich-post-content Specification

## Purpose

Enable illustrated Markdown discussions and meaningful actor mentions while preserving editable source and a strict browser sanitization boundary.

## Requirements

### Requirement: Source-preserving rich display
Local post publication and editing SHALL accept Markdown source, preserve stored source for authorized editing, and add sanitized HTML and explicit content-format metadata to all successful browser post representations. Existing plain display title/body fields SHALL remain compatible. Legacy posts SHALL retain their legacy interpretation until explicitly edited as Markdown. Markdown SHALL support paragraphs, emphasis, lists, headings, blockquotes, code, links, and image references. Raw HTML SHALL NOT bypass sanitization. Remote HTML SHALL be sanitized as HTML and SHALL NOT be reinterpreted as Markdown. Titles SHALL remain plain text.

#### Scenario: Markdown source round trip
- **WHEN** an author publishes Markdown with code and an image reference and retrieves editing source
- **THEN** source equals the stored input subject to documented existing normalization, and display includes the safe formatted content

### Requirement: Allowlist HTML and media references
Every rendered rich-content path SHALL pass through an HTML parser-based allowlist boundary that removes executable elements, event handlers, unsafe attributes, unsafe URL schemes, and active embedded content. Encoded and malformed markup SHALL receive the same protection. Local media references SHALL resolve only to uploads owned by the author and bound to that post; private media SHALL NOT become public through rendering or copying references. External public image references SHALL use source URLs without server-side media fetching or proxying.

#### Scenario: XSS in local or remote content
- **WHEN** content contains JavaScript URLs, event attributes, SVG payloads, encoded attacks, or malformed HTML
- **THEN** the rendered result contains no executable payload while permitted text and formatting remain usable

### Requirement: Structured actor mentions
Mentions SHALL support site-local `@username` and remote `@username@domain`, resolve to canonical Actor identities, and retain structured mention metadata. Parsing SHALL exclude code blocks, inline code, existing link destinations, image destinations, escaped mention markers, and email addresses. Unresolved mentions SHALL remain text. Resolution SHALL be bounded and subject to federation network/block policy. Duplicate mentions SHALL collapse by Actor URI. Editing SHALL notify only newly introduced eligible recipients; removing and later restoring a mention constitutes a new introduction. Mentions SHALL NOT grant membership or expand the target's authorized audience.

#### Scenario: Code and email are not mentions
- **WHEN** a post contains a real mention, the same text in code, and an email address
- **THEN** only the real resolved mention is linked and eligible for notification

#### Scenario: Restricted post mentions an outsider
- **WHEN** a private community post mentions a non-member or a local-only post mentions a remote Actor
- **THEN** no restricted content, notification, or federated delivery reaches that outsider

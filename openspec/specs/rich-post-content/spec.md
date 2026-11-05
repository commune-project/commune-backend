# rich-post-content Specification

## Purpose

Enable illustrated Markdown discussions and meaningful actor mentions while preserving editable source and a strict browser sanitization boundary.

## Requirements

### Requirement: Source-preserving rich display
Local post publication and editing SHALL accept Markdown source, preserve stored source for authorized editing, and add sanitized HTML and explicit content-format metadata to all successful browser post representations. Existing plain display title/body fields SHALL remain compatible. Legacy posts SHALL retain their legacy interpretation until explicitly edited as Markdown. Markdown SHALL support paragraphs, emphasis, strong emphasis, strikethrough, ordered and unordered lists, headings, blockquotes, fenced and indented code, links, autolinks, images, tables, and task-list syntax. Task-list syntax SHALL NOT emit interactive checkbox controls. A single soft line break in Markdown prose SHALL render as a line break. Raw HTML SHALL NOT bypass sanitization; when raw HTML is permitted it SHALL pass through the same allowlist as HTML content and SHALL be removed or reduced when it falls outside that allowlist. Remote HTML SHALL be sanitized as HTML and SHALL NOT be reinterpreted as Markdown. Titles SHALL remain plain text.

#### Scenario: Markdown source round trip
- **WHEN** an author publishes Markdown with code and an image reference and retrieves editing source
- **THEN** source equals the stored input subject to documented existing normalization, and display includes the safe formatted content

#### Scenario: GFM and hard wraps render
- **WHEN** an author publishes Markdown containing a table, strikethrough text, an autolink, a task-list item, and a single line break inside a paragraph
- **THEN** display contains a safe table without alignment markup, deleted text, a link, task-list item text without a checkbox control, and a visible line break

#### Scenario: Raw HTML is filtered
- **WHEN** Markdown or HTML content contains a permitted tag, a tag outside the allowlist, an event handler, or an unsafe URL scheme
- **THEN** permitted formatting survives, the disallowed tag is removed or reduced to its text, and no executable payload remains

### Requirement: Allowlist HTML and media references
Every rendered rich-content path SHALL pass through an HTML parser-based allowlist boundary that removes executable elements, event handlers, unsafe attributes, unsafe URL schemes, and active embedded content. Encoded and malformed markup SHALL receive the same protection. The allowlist SHALL be configurable as a complete element set, a complete per-element attribute set, a complete URL-scheme set, and a relative-URL switch. An absent configuration object SHALL use built-in safe defaults; a present array SHALL replace that category completely, including an explicitly empty array. Configuration validation SHALL reject dangerous elements, attributes, and URL schemes before serving, even when explicitly listed, and SHALL reject malformed element names, attributes attached to unknown elements, and unsupported schemes. The default allowlist SHALL preserve the existing safe elements and add only the elements required by enabled GitHub-flavored syntax. Table alignment SHALL NOT be emitted as `align` or `style`. Image `referrerpolicy` SHALL remain forced to `no-referrer`. Local media references SHALL resolve only to uploads owned by the author and bound to that post; private media SHALL NOT become public through rendering or copying references. External public image references SHALL use source URLs without server-side media fetching or proxying.

#### Scenario: XSS in local or remote content
- **WHEN** content contains JavaScript URLs, event attributes, SVG payloads, encoded attacks, or malformed HTML
- **THEN** the rendered result contains no executable payload while permitted text and formatting remain usable

#### Scenario: Explicit allowlist replaces the default
- **WHEN** a deployment configures an element set containing only `p`, `a`, and `img`
- **THEN** headings, lists, tables, and other omitted elements are not rendered as elements while their text content remains readable

#### Scenario: Empty allowlist removes elements
- **WHEN** a deployment configures an empty element array
- **THEN** rendered output contains escaped text without element markup

#### Scenario: Dangerous configuration is rejected
- **WHEN** a deployment configures `script`, `iframe`, an event attribute, a `style` attribute, or a `javascript:` URL scheme
- **THEN** configuration validation fails before the server starts

#### Scenario: Missing configuration uses defaults
- **WHEN** a deployment omits `rendering`, `rendering.markdown`, or `rendering.sanitize`
- **THEN** rendering uses the built-in safe defaults and behavior matches the shipped example configuration

### Requirement: Structured actor mentions
Mentions SHALL support site-local `@username` and remote `@username@domain`, resolve to canonical Actor identities, and retain structured mention metadata. Parsing SHALL exclude code blocks, inline code, existing link destinations, image destinations, escaped mention markers, and email addresses. Unresolved mentions SHALL remain text. Resolution SHALL be bounded and subject to federation network/block policy. Duplicate mentions SHALL collapse by Actor URI. Editing SHALL notify only newly introduced eligible recipients; removing and later restoring a mention constitutes a new introduction. Mentions SHALL NOT grant membership or expand the target's authorized audience.

#### Scenario: Code and email are not mentions
- **WHEN** a post contains a real mention, the same text in code, and an email address
- **THEN** only the real resolved mention is linked and eligible for notification

#### Scenario: Restricted post mentions an outsider
- **WHEN** a private community post mentions a non-member or a local-only post mentions a remote Actor
- **THEN** no restricted content, notification, or federated delivery reaches that outsider

## Why

Markdown rendering is currently fixed at CommonMark with soft line breaks, raw
HTML dropped before sanitization, and a hard-coded HTML allowlist. Deployments
cannot enable GitHub-flavored syntax or adjust which safe tags and attributes
are permitted without editing Go code, and a single line break does not produce
a visible line break in rendered prose.

## What Changes

- Enable the goldmark GFM extension: tables, strikethrough, autolinks, and task-list
  syntax are parsed. Task-list checkboxes are not rendered as `input` elements and the
  allowlist does not permit `input`.
- Enable `goldmark.WithHardWraps()` so a soft line break in Markdown renders as `<br>`.
  This changes how existing Markdown posts and biographies display. **BREAKING** for
  authored line-break behavior; stored source is unchanged.
- Enable `goldmark.WithUnsafe()` so raw HTML in Markdown reaches the allowlist instead of
  being replaced with an omission comment. Safety is enforced by the same
  parser-based allowlist used for HTML input and remote HTML.
- Add `rendering.markdown` with `hard_wraps` and `allow_raw_html`, and
  `rendering.sanitize` with `elements`, `attributes`, `url_schemes`, and
  `allow_relative_urls`.
- Treat an absent `rendering`, `rendering.markdown`, or `rendering.sanitize` object as
  the built-in default. Treat a present `elements`, `attributes`, or `url_schemes` array
  as a complete replacement, including an explicitly empty array, which removes every
  element, attribute, or scheme.
- Keep a safe default allowlist equivalent to today's set plus the tags required by GFM
  tables and strikethrough. Do not emit table alignment markup. Reject dangerous
  elements, attributes, and URL schemes during configuration validation even when they
  appear in an explicit allowlist.
- Write the default rendering configuration into `config/example.json` and
  `deploy/commune.json`, and add a test that keeps those files equal to the built-in
  defaults.
- Build the sanitizer policy once from validated configuration instead of on every
  render.
- Keep `biography_html` as a snapshot written when a biography is edited. A later
  allowlist change MAY leave stored biography HTML rendered under the previous policy;
  this inconsistency is accepted and documented.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `rich-post-content`: Markdown rendering gains GFM, hard line breaks, allowlisted raw
  HTML, and a validated, configurable sanitizer allowlist with complete-replacement
  semantics.

## Impact

- Rendering pipeline in `internal/content/rich.mygo`, `internal/content/post.mygo`, and
  their generated Go files.
- Rendering configuration in `internal/config/participation.mygo` and validation in
  `internal/config/config.mygo`, plus `config/example.json` and `deploy/commune.json`.
- Browser, profile, and federation callers that render Markdown or sanitize HTML:
  `internal/server/forum.mygo`, `internal/server/profiles.mygo`,
  `internal/federation/representation.mygo`, and `internal/federation/rich.mygo`.
- Documentation in `docs/configuration.md` and `docs/participation-api.md`.
- Display behavior for existing Markdown content changes immediately because post HTML
  is rendered on read; stored biography HTML remains a snapshot.

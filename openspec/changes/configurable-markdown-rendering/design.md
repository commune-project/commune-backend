## Context

See `proposal.md` for motivation and `specs/rich-post-content/spec.md` for the
behavior contract. The current pipeline is `goldmark.New()` followed by a
bluemonday policy rebuilt on every call in `internal/content/rich.mygo`.
`RenderRich(source, format)` is called from post display, profile biography
saving, Person representation, and remote rich-content ingestion. `RenderPostRich`
wraps it for post-specific mention and media rewriting.

Configuration is decoded into `config.Input`, defaulted by `ParticipationDefaults`,
then validated by `Validate` before returning `config.Config`. Rendering settings
currently contain only length and mention bounds. The project builds MyGO sources
into generated Go, and tests run against the generated files.

## Goals / Non-Goals

**Goals:**

- One validated rendering policy shared by every rich-content path.
- GFM parsing with no table alignment output, hard line breaks, and allowlisted
  raw HTML.
- Complete-replacement configuration semantics with a safe built-in default.
- Configuration failure at startup for dangerous or malformed allowlists.
- Example and deployment templates that stay equal to the built-in default.

**Non-Goals:**

- Per-site rendering policies.
- Backfilling or re-rendering stored `biography_html` snapshots.
- Additional goldmark extensions such as footnotes, definition lists, typographer,
  or CJK spacing.
- Frontend styling for newly permitted elements or task-list presentation.
- Changing stored Markdown source, content formats, or federation payload shapes.

## Decisions

### Optional booleans use presence-aware decoding

`hard_wraps` defaults to true and `allow_raw_html` defaults to false, but a
present `false` must remain distinguishable from an omitted field. Go and MyGO
boolean zero values cannot express that distinction. The configuration struct
stores these two fields as `json.RawMessage`, the same pattern already used for
optional profile patch fields, and `Validate` decodes them: absent means default,
present must be a JSON boolean. Alternatives considered: a pointer field, which
MyGO does not model ergonomically, and "any present markdown object overrides the
default", which makes toggling one field silently reset the other.

### The element, attribute, and scheme categories replace independently

An absent `elements`, `attributes`, `url_schemes`, or `allow_relative_urls` field
uses that category's default. A present array replaces the category completely,
and an empty array is a valid explicit empty set. This is verified with nil-versus-
empty slice checks before defaulting, following the existing
`PostAttachmentIDsMissing` pattern. Alternatives considered: an additive
`extra_*` model, which cannot express removal, and merging arrays, which cannot
express an empty set unambiguously.

### The sanitizer is built once and carried in configuration

`internal/content` defines an immutable `Sanitizer` value that wraps a built
bluemonday policy and a constructed goldmark converter. `internal/config`
decodes the policy data, validates it, and constructs the `Sanitizer` during
`Validate`; `Config.Rendering` carries it to every caller. `content` does not
import `config`, so the dependency direction stays one-way and there is no cycle.
Alternatives considered: building the policy in each handler (easy to forget),
and keeping a package-level singleton (hidden global state and untestable
configuration variants).

Bluemonday policies are read-only during sanitization and goldmark Markdown
values are safe for concurrent conversion, so one value can serve all requests.

### Rendering functions take the sanitizer explicitly

`RenderRich` and `RenderPostRich` gain an explicit sanitizer parameter, and every
call site passes the configured value. Keeping a default-policy overload would
let a new call site silently bypass deployment configuration. Tests construct a
default or intentionally restrictive sanitizer directly.

### GFM is composed from individual extensions

The aggregate `extension.GFM` does not expose table options. The converter
registers Linkify, Strikethrough, and TaskList directly, and registers the table
extension as `extension.NewTable(extension.WithTableCellAlignMethod(
extension.TableCellAlignNone))`. This produces tables without `align` or `style`
alignment markup, satisfying the spec without post-processing. Task-list parsing
still occurs, but its `input` element is outside the default allowlist, so the
control is dropped and item text remains.

### Default allowlist and hard rejection set

The default element set is the current set plus `del`, `table`, `thead`, `tbody`,
`tr`, `th`, and `td`. Default attributes remain `a[href,title]`,
`img[src,alt,title,referrerpolicy]`. Default schemes remain `http` and `https`,
and relative URLs remain permitted.

Validation rejects, regardless of configuration: `script`, `style`, `iframe`,
`frame`, `frameset`, `object`, `embed`, `applet`, `template`, `svg`, `math`, `xmp`,
`plaintext`, `title`, `textarea`, `canvas`, `video`, `audio`, `form`, `button`,
`input`, `base`, `meta`, and `link`; attributes named `style`, `srcset`, or
starting with `on`; and schemes other than `http`, `https`, `mailto`, and `tel`.
`javascript:`, `data:`, and `vbscript:` are never accepted. Attribute entries must
reference an element present in the effective element set. Image
`referrerpolicy="no-referrer"` remains forced after sanitization and is not
configurable.

### Defaults are verified against both JSON templates

`config/example.json` and `deploy/commune.json` contain the full default
`rendering` object. A configuration test loads both files, compares the decoded
rendering settings with the built-in default, and fails on drift. An explicit
empty-object test covers `rendering`, `rendering.markdown`, and
`rendering.sanitize` omission separately.

## Risks / Trade-offs

- **Existing Markdown display changes** → Hard wraps alter every soft line break.
  The behavior is configurable, documented as a display change, and stored source
  is untouched.
- **Raw HTML widens the attack surface** → Dangerous elements, attributes, and
  schemes are rejected at startup, the default set stays small, and the existing
  XSS corpus is extended with raw-HTML cases.
- **Complete replacement can strip content unexpectedly** → Both templates show
  the full default, the semantics are documented, and an empty-set test makes the
  outcome explicit.
- **MyGO interface and variadic mapping** → `goldmark.WithExtensions` and renderer
  options accept Go interfaces. A small compile-only spike precedes broader edits,
  and generated Go is never edited by hand.
- **Stored biography HTML may use an older policy** → Accepted. The spec records
  that `biography_html` is a snapshot and only re-edited biographies adopt the
  current allowlist.
- **Sanitizer construction cost moves to startup** → Invalid configuration now
  fails before serving instead of at first render, which is the intended trade-off.

## Migration Plan

No database migration. Existing configuration files remain valid because absent
rendering objects use defaults. Deploy order is configuration first, then the new
binary; older binaries ignore unknown rendering keys during JSON decoding, so a
rollback does not require editing the configuration. After deployment, verify a
Markdown post with a line break, a GFM table, strikethrough, an autolink, and a raw
HTML payload, plus a profile biography edit.

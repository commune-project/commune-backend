## 1. Configuration model and defaults

- [ ] 1.1 Add `Markdown` and `Sanitize` structures under `Rendering` in `internal/config/participation.mygo`, using presence-aware decoding for `hard_wraps` and `allow_raw_html`, and verify the package compiles after MyGO sync.
- [ ] 1.2 Fill absent `rendering`, `rendering.markdown`, and `rendering.sanitize` objects from built-in defaults while preserving explicitly empty arrays, and verify with config unit tests for each omission shape.
- [ ] 1.3 Validate element names, per-element attribute references, URL schemes, and the hard-rejection list; verify `script`, `iframe`, `input`, `on*`, `style`, and `javascript:` configurations fail with a secret-free error.
- [ ] 1.4 Construct the immutable content sanitizer during `Validate` and expose it through `Config.Rendering`, and verify the value is populated for both defaulted and explicit configurations.

## 2. Rendering pipeline

- [ ] 2.1 Add `content.Sanitizer` with a once-built bluemonday policy and a goldmark converter registering Linkify, Strikethrough, TaskList, and `extension.NewTable(extension.WithTableCellAlignMethod(extension.TableCellAlignNone))`, plus hard wraps and unsafe raw-HTML rendering.
- [ ] 2.2 Change `RenderRich` and `RenderPostRich` to take the sanitizer explicitly and update every production and test call site; verify no default-policy overload remains.
- [ ] 2.3 Verify GFM tables render without `align` or `style`, strikethrough and autolinks render, task-list text renders without an `input`, and a single soft line break renders as `<br>`.
- [ ] 2.4 Extend the XSS corpus with raw HTML, disallowed tags, event attributes, `javascript:` and `data:` URLs, encoded markup, and malformed markup; verify no executable payload survives and permitted text remains.
- [ ] 2.5 Verify a restrictive explicit allowlist removes omitted elements while keeping their text, and an empty allowlist produces escaped text without element markup.

## 3. Templates and documentation

- [ ] 3.1 Write the full default `rendering` object into `config/example.json` and verify `commune check-config config/example.json` succeeds.
- [ ] 3.2 Write the same defaults into `deploy/commune.json` and verify `commune check-config deploy/commune.json` succeeds after substituting a test database URL.
- [ ] 3.3 Add a configuration test that decodes both JSON templates and fails when their rendering settings differ from the built-in defaults.
- [ ] 3.4 Document the complete-replacement semantics, GFM behavior, hard wraps, raw-HTML policy, rejection list, and the accepted `biography_html` snapshot inconsistency in `docs/configuration.md` and `docs/participation-api.md`.

## 4. Integration verification

- [ ] 4.1 Bootstrap-sync packages in dependency order (`content`, then `config`, then `server` and `federation`) and verify `go test -run '^$'` compiles every affected package.
- [ ] 4.2 Run focused content, config, server, and federation rendering tests and verify all pass without skipped fixtures.
- [ ] 4.3 Exercise a Markdown post containing a table, strikethrough, autolink, task list, soft line break, and raw HTML payload through the browser API, and verify the JSON body HTML matches the spec.
- [ ] 4.4 Edit a profile biography under a restrictive allowlist and verify the stored `biography_html` reflects the policy at save time while an existing biography keeps its earlier snapshot.
- [ ] 4.5 Run `openspec validate configurable-markdown-rendering --strict` and verify it passes.

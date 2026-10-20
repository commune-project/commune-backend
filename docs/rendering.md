# Text rendering

`content.RenderText` is the display boundary. It removes comments and dangerous
elements with their contents (`script`, `style`, `noscript`, `iframe`, `object`,
`embed`, `svg`, `math`, `template`, `form`, and similar), strips remaining tags,
then escapes `&`, `<`, `>`, `"` and `'`. Inline event handlers and
`javascript:` URLs cannot survive because no tag or attribute is kept. Output is
plain text that cannot introduce markup.

Rendering never rewrites stored content. `PostRepository.Receive` and `Publish`
store the protocol body verbatim, and callers compute display text on read, so
the retained inbound payload stays unchanged for forwarding and signatures.
`render_separation_test.mygo` verifies the stored body is byte-identical after
rendering, and `render_test.mygo` covers script, style, iframe, svg, comment,
entity and stray-angle-bracket cases.

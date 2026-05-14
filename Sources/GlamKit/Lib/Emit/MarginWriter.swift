import Foundation

/// Applies indent + margin around an already-wrapped block of text.
/// Glamour does this as a stream-of-runes pipeline (`MarginWriter` →
/// `PaddingWriter` → `IndentWriter`), which is necessary in their
/// case because rendering happens inside goldmark's NodeRenderer
/// callbacks. In our walk we have the full block in hand at finish
/// time, so we can do this as a single per-line transform.
public enum MarginWriter {

    /// Apply margin (`margin` columns of leading space outside the
    /// indent) and indent (`indent` columns of `indentToken` inside
    /// the margin) to every line of `content`.
    ///
    /// When `fillBackground` is `true` AND `style.backgroundColor`
    /// is non-nil, each line is right-padded with spaces to `width`
    /// columns so the bg extends across the full block area —
    /// what real glamour does for code blocks, block quotes, etc.
    /// Inline-styled elements (headings, emphasis runs) leave
    /// `fillBackground = false` so their bg covers only the text +
    /// prefix/suffix, matching upstream glamour's H1 / H2 rendering.
    public static func apply(
        _ content: String,
        indent: Int,
        indentToken: String,
        margin: Int,
        width: Int,
        style: StylePrimitive,
        fillBackground: Bool,
        on terminal: Terminal
    ) -> String {
        let leadingMargin = String(repeating: " ", count: max(0, margin))
        let indentRun = indent > 0
            ? String(repeating: indentToken, count: indent)
            : ""

        // Inline prefix / suffix go INSIDE the SGR envelope so the
        // styled fg/bg covers them — matches upstream glamour's
        // " SwiftBash " rendering where the leading/trailing space
        // is part of the heading's coloured bar. (`block_prefix` /
        // `block_suffix` stay OUTSIDE the envelope, applied
        // separately by `prefixSuffixed` in the renderer.)
        let inlinePrefix = style.prefix ?? ""
        let inlineSuffix = style.suffix ?? ""
        let prefixWidth = Wrap.printWidth(inlinePrefix)
        let suffixWidth = Wrap.printWidth(inlineSuffix)

        let needsRightPad = fillBackground && style.backgroundColor != nil
        let (open, close) = Styled.envelope(style, on: terminal)

        var lines: [String] = []
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if needsRightPad {
                // Padding sees the prefix + content + suffix as the
                // styled run we need to fill against `width`.
                let printed = prefixWidth + Wrap.printWidth(line) + suffixWidth
                if printed < width {
                    line += String(repeating: " ", count: width - printed)
                }
            }
            let styledRun = inlinePrefix + line + inlineSuffix
            let wrapped = open + styledRun + close
            lines.append(leadingMargin + indentRun + wrapped)
        }
        return lines.joined(separator: "\n")
    }
}

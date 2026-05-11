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
    /// the margin) to every line of `content`. Trailing-edge padding
    /// to `width` is applied when `style.backgroundColor != nil` —
    /// otherwise the background color wouldn't extend to the full
    /// terminal column, leaving a ragged colored bar.
    public static func apply(
        _ content: String,
        indent: Int,
        indentToken: String,
        margin: Int,
        width: Int,
        style: StylePrimitive,
        on terminal: Terminal
    ) -> String {
        let leadingMargin = String(repeating: " ", count: max(0, margin))
        let indentRun = indent > 0
            ? String(repeating: indentToken, count: indent)
            : ""

        let needsRightPad = style.backgroundColor != nil
        let (open, close) = Styled.envelope(style, on: terminal)

        var lines: [String] = []
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if needsRightPad {
                let printed = Wrap.printWidth(line)
                if printed < width {
                    line += String(repeating: " ", count: width - printed)
                }
            }
            let wrapped = open + line + close
            lines.append(leadingMargin + indentRun + wrapped)
        }
        return lines.joined(separator: "\n")
    }
}

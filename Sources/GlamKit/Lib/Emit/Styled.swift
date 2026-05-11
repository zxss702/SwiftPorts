import Foundation

/// Applies a `StylePrimitive` to a string, returning the resulting
/// ANSI-wrapped text. Mirrors glamour's `renderText` from
/// `ansi/baseelement.go`.
public enum Styled {

    /// Build the SGR envelope for `style` on `terminal`. Returns
    /// `("", "")` when nothing would render (no color, no flags), so
    /// callers can prepend/append unconditionally.
    public static func envelope(
        _ style: StylePrimitive,
        on terminal: Terminal
    ) -> (open: String, close: String) {
        guard terminal.colorEnabled else { return ("", "") }

        var fragments: [String?] = []
        if let c = style.color           { fragments.append(Color.fg(c, on: terminal)) }
        if let c = style.backgroundColor { fragments.append(Color.bg(c, on: terminal)) }
        if style.bold        == true { fragments.append("1") }
        if style.faint       == true { fragments.append("2") }
        if style.italic      == true { fragments.append("3") }
        if style.underline   == true { fragments.append("4") }
        if style.blink       == true { fragments.append("5") }
        if style.inverse     == true { fragments.append("7") }
        if style.conceal     == true { fragments.append("8") }
        if style.crossedOut  == true { fragments.append("9") }
        let open = Color.envelope(fragments)
        return (open, open.isEmpty ? "" : Color.reset)
    }

    /// Render an inline run of text with `style` applied. Honors the
    /// `upper` / `lower` / `title` case modifiers from glamour.
    public static func render(
        _ text: String,
        style: StylePrimitive,
        on terminal: Terminal
    ) -> String {
        var s = text
        if style.upper == true { s = s.uppercased() }
        if style.lower == true { s = s.lowercased() }
        if style.title == true { s = s.capitalized }
        let (open, close) = envelope(style, on: terminal)
        return open + s + close
    }

    /// Apply the `format` template, restricted to the single token
    /// glamour's bundled styles actually use (`{{.text}}`). The Go
    /// `text/template` engine ranges further than that, but the only
    /// bundled formats are `"Image: {{.text}} →"` and the hr's
    /// `"\n--------\n"` (no template) — we cover both.
    public static func applyFormat(_ format: String?, to text: String) -> String {
        guard let fmt = format, !fmt.isEmpty else { return text }
        return fmt.replacingOccurrences(of: "{{.text}}", with: text)
    }
}

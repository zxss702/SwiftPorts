import Foundation

/// Word-wrap that's aware of ANSI escape sequences (doesn't count
/// them toward width) and respects existing newlines. We do *not*
/// implement wcwidth-precise CJK width here — gh/glab content is
/// overwhelmingly ASCII; if/when that matters we add a width table.
public enum Wrap {
    /// Soft-wrap `s` to at most `width` printable columns per line.
    /// `width == 0` disables wrapping (returns input unchanged).
    public static func wrap(_ s: String, width: Int) -> String {
        guard width > 0, !s.isEmpty else { return s }

        var out: [String] = []
        for paragraph in s.split(separator: "\n", omittingEmptySubsequences: false) {
            out.append(wrapLine(String(paragraph), width: width))
        }
        return out.joined(separator: "\n")
    }

    /// Print width — characters that occupy column space, ignoring
    /// ANSI CSI / OSC escape sequences.
    public static func printWidth(_ s: String) -> Int {
        var width = 0
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\u{1B}" {
                // Skip escape sequence: CSI ends at any byte in 0x40-0x7E,
                // OSC ends at BEL (0x07) or ST (ESC \). Fast generic skip.
                i = s.index(after: i)
                if i < s.endIndex, s[i] == "]" {
                    // OSC — skip until BEL or ESC\
                    while i < s.endIndex, s[i] != "\u{07}" {
                        if s[i] == "\u{1B}" {
                            let next = s.index(after: i)
                            if next < s.endIndex, s[next] == "\\" {
                                i = s.index(after: next)
                                break
                            }
                        }
                        i = s.index(after: i)
                    }
                    if i < s.endIndex { i = s.index(after: i) }
                    continue
                }
                if i < s.endIndex, s[i] == "[" {
                    i = s.index(after: i)
                    while i < s.endIndex {
                        let ch = s[i]
                        i = s.index(after: i)
                        if ch.asciiValue.map({ (0x40...0x7E).contains(Int($0)) }) == true {
                            break
                        }
                    }
                    continue
                }
                // Other escape — skip one
                if i < s.endIndex { i = s.index(after: i) }
                continue
            }
            width += 1
            i = s.index(after: i)
        }
        return width
    }

    private static func wrapLine(_ line: String, width: Int) -> String {
        if printWidth(line) <= width { return line }

        var result = ""
        var current = ""
        var currentWidth = 0

        for token in tokenize(line) {
            let tokenWidth = printWidth(token.text)
            if token.isWhitespace {
                // Hold the whitespace — only commit it if we don't wrap
                // immediately after.
                if currentWidth + tokenWidth > width {
                    if !result.isEmpty { result += "\n" }
                    result += current
                    current = ""
                    currentWidth = 0
                    continue
                }
                current += token.text
                currentWidth += tokenWidth
            } else {
                if currentWidth + tokenWidth > width, !current.isEmpty {
                    if !result.isEmpty { result += "\n" }
                    result += current.trimmingTrailingWhitespace()
                    current = ""
                    currentWidth = 0
                }
                current += token.text
                currentWidth += tokenWidth
            }
        }
        if !current.isEmpty {
            if !result.isEmpty { result += "\n" }
            result += current
        }
        return result
    }

    private struct Token { let text: String; let isWhitespace: Bool }

    private static func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        var buf = ""
        var inWS: Bool? = nil
        for ch in s {
            let isWS = ch.isWhitespace
            if inWS == nil { inWS = isWS }
            if isWS == inWS! {
                buf.append(ch)
            } else {
                out.append(Token(text: buf, isWhitespace: inWS!))
                buf = String(ch)
                inWS = isWS
            }
        }
        if !buf.isEmpty, let ws = inWS {
            out.append(Token(text: buf, isWhitespace: ws))
        }
        return out
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var s = self
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return s
    }
}

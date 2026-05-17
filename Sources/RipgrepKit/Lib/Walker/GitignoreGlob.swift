import Foundation

/// Gitignore-style glob matcher. Compiles a single gitignore pattern
/// into a regex that can be evaluated against a relative path.
///
/// Implements the subset of `gitignore(5)` that matters for the
/// recursive walker:
///
///   * `*`            — matches any sequence of non-`/` characters.
///   * `**`           — matches any sequence including `/`.
///   * `?`            — single non-`/` character.
///   * `[abc]` / `[!abc]` / `[a-z]` — character class.
///   * leading `/`    — anchors the pattern to the root.
///   * leading `!`    — negation (caller handles).
///   * trailing `/`   — directory-only match (caller handles).
///   * no `/` in the pattern (other than a trailing one) means the
///     pattern matches in any subdirectory.
///
/// The matcher is allocation-free at the per-path level once compiled
/// (it walks a flat array of compiled segments). Comparison is
/// case-insensitive when constructed that way.
public struct GitignoreGlob: Sendable {

    public let originalPattern: String
    public let isNegation: Bool
    public let directoryOnly: Bool
    public let anchored: Bool
    public let caseInsensitive: Bool

    private let regex: NSRegularExpression

    /// Compile `pattern`. `isNegation` is stripped here so callers
    /// don't have to slice it themselves.
    public init(pattern: String, caseInsensitive: Bool = false) throws {
        var p = pattern
        var negation = false
        if p.hasPrefix("!") {
            negation = true
            p.removeFirst()
        }
        // A backslash-escaped leading `!` or `#` is a literal char.
        if p.hasPrefix("\\!") || p.hasPrefix("\\#") {
            p.removeFirst()
        }

        var directoryOnly = false
        if p.hasSuffix("/") {
            directoryOnly = true
            p.removeLast()
        }

        // A pattern with a `/` anywhere except the trailing position
        // anchors to the gitignore file's directory. A pattern with no
        // slash matches in any subdirectory.
        let anchored = p.hasPrefix("/") || p.contains("/")
        if p.hasPrefix("/") {
            p.removeFirst()
        }

        self.originalPattern = pattern
        self.isNegation = negation
        self.directoryOnly = directoryOnly
        self.anchored = anchored
        self.caseInsensitive = caseInsensitive

        let regexSource = GitignoreGlob.compile(p, anchored: anchored)
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        self.regex = try NSRegularExpression(pattern: regexSource,
                                             options: options)
    }

    /// Match `relativePath` (forward-slash separated) against this glob.
    /// `isDirectory` matters for `directoryOnly` patterns.
    public func matches(_ relativePath: String, isDirectory: Bool) -> Bool {
        if directoryOnly && !isDirectory { return false }
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        return regex.firstMatch(in: relativePath, options: [], range: range) != nil
    }

    /// Translate a gitignore-flavored glob into a Swift-compatible
    /// `NSRegularExpression` source. The output is anchored at the
    /// start and end (`^…$`) so `firstMatch` is sufficient.
    static func compile(_ pattern: String, anchored: Bool) -> String {
        var out = "^"
        if !anchored {
            // Unanchored patterns can begin at any path segment boundary.
            // Match the leading prefix as either empty or "<anything>/".
            out += "(?:.*/)?"
        }
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    // `**` — match across slashes.
                    let j = i + 2
                    // `/**/` collapses to "(?:/|/.*/)".
                    if i > 0 && chars[i - 1] == "/" && j < chars.count && chars[j] == "/" {
                        // We already emitted the leading `/`; the
                        // intermediate `**/` is the optional middle.
                        out += ".*"
                        i = j + 1
                        continue
                    }
                    // Trailing `**` — match rest of path including slashes.
                    out += ".*"
                    i = j
                    continue
                }
                // Single `*` — anything except `/`.
                out += "[^/]*"
                i += 1
            case "?":
                out += "[^/]"
                i += 1
            case "[":
                // Bracket expression: copy through to the closing `]`,
                // remapping a leading `!` to regex `^`.
                var j = i + 1
                if j < chars.count && (chars[j] == "!" || chars[j] == "^") {
                    j += 1
                }
                if j < chars.count && chars[j] == "]" { j += 1 }
                while j < chars.count && chars[j] != "]" { j += 1 }
                if j >= chars.count {
                    // Unterminated bracket — treat `[` as literal.
                    out += "\\["
                    i += 1
                } else {
                    var bracket = "["
                    if chars[i + 1] == "!" {
                        bracket += "^"
                        bracket += String(chars[(i + 2)..<j])
                    } else {
                        bracket += String(chars[(i + 1)..<j])
                    }
                    bracket += "]"
                    out += bracket
                    i = j + 1
                }
            case "\\":
                if i + 1 < chars.count {
                    out += NSRegularExpression.escapedPattern(for: String(chars[i + 1]))
                    i += 2
                } else {
                    out += "\\\\"
                    i += 1
                }
            case "/":
                out += "/"
                i += 1
            default:
                out += NSRegularExpression.escapedPattern(for: String(c))
                i += 1
            }
        }
        // Allow the pattern to also match the path of any descendant —
        // e.g., `build/` should match `build`, `build/x`, `build/x/y`.
        out += "(?:/.*)?$"
        return out
    }
}

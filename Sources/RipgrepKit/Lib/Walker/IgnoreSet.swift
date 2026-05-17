import Foundation

/// A stack of compiled `.gitignore` / `.ignore` / `.rgignore` files.
///
/// Each level in the stack carries the patterns harvested from one
/// directory plus its base path. The whole-tree walker pushes / pops
/// levels as it descends and ascends. Matching is performed
/// most-specific-first: deeper rules win over shallower rules, and
/// within the same file later rules win over earlier ones — exactly
/// matching `gitignore(5)` semantics.
public struct IgnoreSet: Sendable {

    public struct Entry: Sendable {
        public let glob: GitignoreGlob
        /// The directory the pattern was harvested in, relative to the
        /// walker root. Patterns are matched against
        /// `pathRelativeToBase = pathRelativeToRoot - base`.
        public let baseRelativeToRoot: String

        public init(glob: GitignoreGlob, baseRelativeToRoot: String) {
            self.glob = glob
            self.baseRelativeToRoot = baseRelativeToRoot
        }
    }

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public mutating func append(_ entry: Entry) {
        entries.append(entry)
    }

    public mutating func append(contentsOf newEntries: [Entry]) {
        entries.append(contentsOf: newEntries)
    }

    /// Drop entries pushed since `mark`, returning to that snapshot.
    public mutating func truncate(to mark: Int) {
        if entries.count > mark {
            entries.removeLast(entries.count - mark)
        }
    }

    /// Matched flag — `nil` if no pattern applies, `true` if the path
    /// is ignored, `false` if the path is explicitly un-ignored via a
    /// `!negation`.
    public enum Decision: Sendable {
        case none
        case ignore
        case allow
    }

    /// Decide whether `pathRelativeToRoot` is ignored.
    ///
    /// `isDirectory` matters for trailing-slash patterns. We iterate
    /// `entries` in order (oldest first) and keep the final decision —
    /// later rules override earlier ones.
    public func decide(pathRelativeToRoot: String,
                       isDirectory: Bool) -> Decision {
        var current: Decision = .none
        for entry in entries {
            let rel = stripBase(entry.baseRelativeToRoot,
                                from: pathRelativeToRoot)
            guard let rel else { continue }
            if entry.glob.matches(rel, isDirectory: isDirectory) {
                current = entry.glob.isNegation ? .allow : .ignore
            }
        }
        return current
    }

    /// Strip a directory-prefix and the leading `/`. Returns `nil` if
    /// `path` is not under `base`.
    private func stripBase(_ base: String, from path: String) -> String? {
        if base.isEmpty { return path }
        if path == base { return "" }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    // MARK: - Parsing

    /// Parse a gitignore-formatted file. Blank lines and `#`-prefixed
    /// comments are skipped. CRLF is tolerated.
    public static func parse(contents: String,
                             baseRelativeToRoot: String,
                             caseInsensitive: Bool = false) -> [Entry] {
        var out: [Entry] = []
        for rawLine in contents.split(omittingEmptySubsequences: false,
                                      whereSeparator: { $0 == "\n" }) {
            var line = String(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            // Trailing whitespace ignored unless escaped.
            line = trimGitignoreTrailingWhitespace(line)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }
            do {
                let glob = try GitignoreGlob(pattern: line,
                                             caseInsensitive: caseInsensitive)
                out.append(Entry(glob: glob,
                                 baseRelativeToRoot: baseRelativeToRoot))
            } catch {
                continue
            }
        }
        return out
    }

    private static func trimGitignoreTrailingWhitespace(_ s: String) -> String {
        // git treats trailing spaces as significant only when
        // backslash-escaped. We follow the same rule.
        var chars = Array(s)
        while let last = chars.last, last == " " || last == "\t" {
            // Look behind for an escaping backslash.
            if chars.count >= 2 && chars[chars.count - 2] == "\\" {
                break
            }
            chars.removeLast()
        }
        return String(chars)
    }
}

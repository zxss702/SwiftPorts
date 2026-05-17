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
        /// `pathRelativeToBase = pathRelativeToRoot - base`. Used when
        /// `baseAbsolute` is nil.
        public let baseRelativeToRoot: String
        /// Absolute path of the directory the pattern was harvested in.
        /// When set, matching strips this prefix from the candidate's
        /// absolute path. Used for entries loaded above the walker root
        /// — parent-directory ignores — where there's no sensible
        /// walker-root-relative base.
        public let baseAbsolute: String?

        public init(glob: GitignoreGlob,
                    baseRelativeToRoot: String,
                    baseAbsolute: String? = nil) {
            self.glob = glob
            self.baseRelativeToRoot = baseRelativeToRoot
            self.baseAbsolute = baseAbsolute
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

    /// Decide whether a path is ignored.
    ///
    /// `pathRelativeToRoot` drives matching for entries loaded from
    /// inside the walker root (the common case). `pathAbsolute` (when
    /// available) drives matching for entries loaded from above the
    /// root — e.g. parent-directory gitignores.
    ///
    /// `isDirectory` matters for trailing-slash patterns. Entries are
    /// iterated oldest first; later rules override earlier ones to
    /// match `gitignore(5)` semantics.
    public func decide(pathRelativeToRoot: String,
                       pathAbsolute: String? = nil,
                       isDirectory: Bool) -> Decision {
        var current: Decision = .none
        for entry in entries {
            let rel: String?
            if let absBase = entry.baseAbsolute {
                guard let absPath = pathAbsolute else { continue }
                rel = stripBase(absBase, from: absPath)
            } else {
                rel = stripBase(entry.baseRelativeToRoot,
                                from: pathRelativeToRoot)
            }
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
    ///
    /// Pass `baseAbsolute` when the file lives above the walker root
    /// (parent-directory ignores); matching strips that prefix from
    /// the candidate's absolute path. Leave `baseAbsolute` nil for
    /// in-root or global ignores; matching uses `baseRelativeToRoot`
    /// against the path relative to the walker root.
    public static func parse(contents: String,
                             baseRelativeToRoot: String,
                             baseAbsolute: String? = nil,
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
                                 baseRelativeToRoot: baseRelativeToRoot,
                                 baseAbsolute: baseAbsolute))
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

import Foundation

/// Options that shape the name-matching half of `fd`.
///
/// Unlike ripgrep — which always reads regex patterns against file
/// contents — fd accepts patterns in three flavors and applies them to
/// entry names (or full paths). The default flavor is regex, matching
/// the upstream tool's behavior.
public struct PatternOptions: Sendable {

    /// How the pattern string should be interpreted.
    public enum Syntax: Sendable {
        /// Treat the pattern as a regular expression (default).
        case regex
        /// `-g` / `--glob` — treat the pattern as a shell-style glob.
        /// `*` matches any run of characters (sans `/`), `**` matches
        /// across path separators, `?` is one character, `[abc]` is a
        /// character class.
        case glob
        /// `-F` / `--fixed-strings` — literal substring search, no
        /// regex metacharacters.
        case fixedString
    }

    /// Case-handling strategy. Mirrors ripgrep's tri-state.
    public enum CaseMode: Sendable {
        case smartCase
        case ignoreCase
        case caseSensitive
    }

    /// The user-supplied pattern. Empty means "match everything", same
    /// as upstream fd's no-pattern invocation.
    public var pattern: String = ""

    /// How `pattern` should be parsed.
    public var syntax: Syntax = .regex

    /// Case-handling mode for `pattern`.
    public var caseMode: CaseMode = .smartCase

    /// Match against the entry's full path instead of just the basename
    /// (`-p` / `--full-path`).
    public var matchFullPath: Bool = false

    /// Only emit entries whose extension is one of these. The list is
    /// compared against `URL.pathExtension` (case-insensitive). Mirrors
    /// `-e EXT` (repeatable).
    public var extensions: [String] = []

    public init() {}
}

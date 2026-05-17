import Foundation

/// Options that shape how the user's raw pattern(s) get compiled into
/// a `PatternMatcher`.
public struct PatternOptions: Sendable {

    /// The raw patterns. `rg PATTERN` and `rg -e PAT1 -e PAT2` both
    /// land here as `[..]`. Patterns are OR-combined.
    public var patterns: [String] = []

    /// Treat patterns as literal strings rather than regexes
    /// (`-F`/`--fixed-strings`).
    public var fixedStrings: Bool = false

    /// Match only when the pattern is surrounded by word boundaries
    /// (`-w`/`--word-regexp`).
    public var wordRegexp: Bool = false

    /// Require the pattern to span the whole line (`-x`/`--line-regexp`).
    public var lineRegexp: Bool = false

    /// Case behaviour. `caseSensitive` is the default.
    public var caseMode: CaseMode = .caseSensitive

    /// Invert match — emit lines that do NOT match (`-v`).
    public var invertMatch: Bool = false

    /// Enable multi-line regex matching across `\n` (`-U`).
    public var multiline: Bool = false

    /// Make `.` match `\n` in multi-line mode (`--multiline-dotall`).
    public var multilineDotall: Bool = false

    public init() {}

    public enum CaseMode: Sendable, Equatable {
        case caseSensitive
        case ignoreCase
        /// Case sensitive unless the pattern is all-lowercase.
        case smartCase
    }
}

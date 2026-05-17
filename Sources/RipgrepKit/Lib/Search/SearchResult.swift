import Foundation

/// Result data the searcher hands off to the printer.

/// A matching line and its match offsets.
public struct LineMatch: Sendable {
    /// 1-indexed line number.
    public let lineNumber: Int
    /// Cumulative byte offset (from file start) of the line's first byte.
    public let byteOffset: Int
    /// Line content (without the trailing terminator).
    public let line: String
    /// UTF-8 byte spans inside `line` that the pattern matched.
    public let hits: [PatternMatcher.Hit]

    public init(lineNumber: Int,
                byteOffset: Int,
                line: String,
                hits: [PatternMatcher.Hit]) {
        self.lineNumber = lineNumber
        self.byteOffset = byteOffset
        self.line = line
        self.hits = hits
    }
}

/// A context line associated with a nearby match (before / after).
public struct ContextLine: Sendable {
    public let lineNumber: Int
    public let byteOffset: Int
    public let line: String

    public init(lineNumber: Int, byteOffset: Int, line: String) {
        self.lineNumber = lineNumber
        self.byteOffset = byteOffset
        self.line = line
    }
}

/// One "chunk" of contiguous output for a file — a match plus its
/// optional context lines. Adjacent chunks that overlap are merged
/// upstream so the printer doesn't have to deduplicate.
public struct SearchChunk: Sendable {
    public let before: [ContextLine]
    public let match: LineMatch
    public let after: [ContextLine]

    public init(before: [ContextLine],
                match: LineMatch,
                after: [ContextLine]) {
        self.before = before
        self.match = match
        self.after = after
    }
}

/// Whole-file result. The printer consumes this to decide on heading,
/// summary, etc.
public struct FileSearchResult: Sendable {
    /// Display path (what the user typed / what the walker resolved).
    public let displayPath: String
    /// Total matching lines, post-`maxCount`.
    public let lineMatches: Int
    /// Total individual matches across all lines.
    public let totalMatches: Int
    /// The chunks the printer should emit. Empty if `--files-without-match`
    /// is desired and there was nothing.
    public let chunks: [SearchChunk]
    /// True if the file was binary (and detected as such) — drives the
    /// "binary file matches" terse summary.
    public let binary: Bool
    /// Approximate bytes scanned. Used for `--stats`.
    public let bytesSearched: Int

    public init(displayPath: String,
                lineMatches: Int,
                totalMatches: Int,
                chunks: [SearchChunk],
                binary: Bool,
                bytesSearched: Int) {
        self.displayPath = displayPath
        self.lineMatches = lineMatches
        self.totalMatches = totalMatches
        self.chunks = chunks
        self.binary = binary
        self.bytesSearched = bytesSearched
    }

    public var hasMatch: Bool { lineMatches > 0 }
}

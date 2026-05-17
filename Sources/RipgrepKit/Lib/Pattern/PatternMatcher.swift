import Foundation

/// A compiled pattern matcher. Backed by `NSRegularExpression`; mirrors
/// ripgrep's matching semantics closely enough for the common cases.
public struct PatternMatcher: Sendable {

    public let options: PatternOptions
    private let regex: NSRegularExpression

    public init(_ options: PatternOptions) throws {
        guard !options.patterns.isEmpty else {
            throw PatternError.noPattern
        }
        self.options = options
        self.regex = try PatternMatcher.compile(options)
    }

    /// A single hit inside a line.
    public struct Hit: Sendable {
        public let utf8Start: Int
        public let utf8End: Int

        public init(utf8Start: Int, utf8End: Int) {
            self.utf8Start = utf8Start
            self.utf8End = utf8End
        }

        public var length: Int { utf8End - utf8Start }
    }

    /// Find every match in `line` (as a UTF-8-decoded `String`).
    /// Returns offsets in `line.utf8` so the caller can colorize
    /// without `String.Index` gymnastics.
    public func findAll(in line: String) -> [Hit] {
        let nsLine = line as NSString
        let nsRange = NSRange(location: 0, length: nsLine.length)
        var hits: [Hit] = []
        regex.enumerateMatches(in: line, options: [], range: nsRange) { result, _, _ in
            guard let result else { return }
            let r = result.range
            // Convert from UTF-16 indices to UTF-8 byte offsets so the
            // printer can paint highlights without reasoning about
            // surrogate pairs at the byte level.
            let prefix = nsLine.substring(with: NSRange(location: 0, length: r.location))
            let matchStr = nsLine.substring(with: r)
            let u8Start = prefix.utf8.count
            let u8End = u8Start + matchStr.utf8.count
            hits.append(Hit(utf8Start: u8Start, utf8End: u8End))
        }
        return hits
    }

    /// Quick yes/no test, faster than `findAll` when the caller only
    /// cares whether the line matches.
    public func isMatch(line: String) -> Bool {
        if options.invertMatch {
            return !hasAnyMatch(line: line)
        }
        return hasAnyMatch(line: line)
    }

    /// Run the underlying regex once.
    private func hasAnyMatch(line: String) -> Bool {
        let nsLine = line as NSString
        let nsRange = NSRange(location: 0, length: nsLine.length)
        return regex.firstMatch(in: line, options: [], range: nsRange) != nil
    }

    // MARK: - Compilation

    private static func compile(_ opts: PatternOptions) throws -> NSRegularExpression {
        let alts = opts.patterns.map { rawAlt in
            transform(pattern: rawAlt, opts: opts)
        }
        // OR-combine. Each alternative is grouped non-capture so word/
        // line wrappers behave as a unit.
        let combined: String
        if alts.count == 1 {
            combined = alts[0]
        } else {
            combined = alts.map { "(?:\($0))" }.joined(separator: "|")
        }

        var nsOptions: NSRegularExpression.Options = []
        switch opts.caseMode {
        case .ignoreCase:
            nsOptions.insert(.caseInsensitive)
        case .smartCase:
            let allLower = opts.patterns.allSatisfy {
                $0.lowercased() == $0
            }
            if allLower { nsOptions.insert(.caseInsensitive) }
        case .caseSensitive:
            break
        }
        if opts.multiline && opts.multilineDotall {
            nsOptions.insert(.dotMatchesLineSeparators)
        }
        // `^`/`$` per-line in both multi-line and single-line scans.
        nsOptions.insert(.anchorsMatchLines)

        do {
            return try NSRegularExpression(pattern: combined, options: nsOptions)
        } catch {
            throw PatternError.invalidRegex(pattern: combined,
                                            underlying: error)
        }
    }

    private static func transform(pattern: String, opts: PatternOptions) -> String {
        var p = pattern
        if opts.fixedStrings {
            p = NSRegularExpression.escapedPattern(for: p)
        }
        if opts.wordRegexp {
            p = "\\b(?:\(p))\\b"
        }
        if opts.lineRegexp {
            p = "^(?:\(p))$"
        }
        return p
    }
}

public enum PatternError: Error, CustomStringConvertible, Sendable {
    case noPattern
    case invalidRegex(pattern: String, underlying: Error)

    public var description: String {
        switch self {
        case .noPattern:
            return "no pattern supplied"
        case let .invalidRegex(pattern, underlying):
            return "invalid regex '\(pattern)': \(underlying.localizedDescription)"
        }
    }
}

import Foundation
import RipgrepKit

/// Pattern-matching error surface. Distinct name from RipgrepKit's
/// `PatternError` so a caller that imports both kits doesn't get a
/// type-lookup ambiguity.
public struct FdPatternError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// Compiles a `PatternOptions` value into a callable matcher. The
/// matcher takes a (basename, relativePath) pair and answers whether
/// the entry should be emitted.
///
/// Upstream fd implements three pattern syntaxes — regex (default),
/// shell glob (`-g`), and literal substring (`-F`). All three are
/// reduced to an `NSRegularExpression` here so the per-entry path
/// only walks one engine.
public struct PatternMatcher: Sendable {

    private let regex: NSRegularExpression?
    private let matchFullPath: Bool
    private let extensions: [String]

    public init(_ options: PatternOptions) throws {
        self.matchFullPath = options.matchFullPath
        self.extensions = options.extensions.map { $0.lowercased() }

        // An empty pattern matches every entry (fd's no-pattern mode).
        if options.pattern.isEmpty {
            self.regex = nil
            return
        }

        let body: String
        switch options.syntax {
        case .regex:
            body = options.pattern
        case .fixedString:
            body = NSRegularExpression.escapedPattern(for: options.pattern)
        case .glob:
            // Reuse the gitignore glob compiler from RipgrepKit. For
            // fd, globs are anchored to the basename when
            // `--full-path` is off — the GitignoreGlob compile path
            // accepts a flag for that.
            body = GitignoreGlob.compile(options.pattern,
                                         anchored: options.matchFullPath)
            // GitignoreGlob.compile produces a fully-anchored regex
            // (`^…$`). Skip the case-folding insertion below by
            // building the NSRegularExpression directly.
            var regexOptions: NSRegularExpression.Options = []
            switch options.caseMode {
            case .ignoreCase:
                regexOptions.insert(.caseInsensitive)
            case .caseSensitive:
                break
            case .smartCase:
                if !options.pattern.contains(where: { $0.isUppercase }) {
                    regexOptions.insert(.caseInsensitive)
                }
            }
            do {
                self.regex = try NSRegularExpression(pattern: body,
                                                     options: regexOptions)
            } catch {
                throw FdPatternError(message: "invalid glob '\(options.pattern)': \(error.localizedDescription)")
            }
            return
        }

        var regexOptions: NSRegularExpression.Options = []
        switch options.caseMode {
        case .ignoreCase:
            regexOptions.insert(.caseInsensitive)
        case .caseSensitive:
            break
        case .smartCase:
            if !options.pattern.contains(where: { $0.isUppercase }) {
                regexOptions.insert(.caseInsensitive)
            }
        }

        do {
            self.regex = try NSRegularExpression(pattern: body,
                                                 options: regexOptions)
        } catch {
            throw FdPatternError(message: "invalid pattern '\(options.pattern)': \(error.localizedDescription)")
        }
    }

    /// Locate the pattern's hit within `path` for match-highlighting.
    ///
    /// Mirrors fd's own behavior: the matched region is painted by the
    /// printer in a contrasting color so users can see *why* an entry
    /// was returned. Returns the byte range within `path` that should
    /// be highlighted, or `nil` if there is no regex (empty-pattern
    /// mode, or the run is in pure-extension-filter mode).
    ///
    /// `path` is whatever the printer is about to emit — possibly the
    /// `displayPath`, possibly the absolute form, possibly with a
    /// trailing `/` from `directorySlash` decoration. The matcher
    /// re-runs its regex against either the basename slice of `path`
    /// (default) or the whole string (`--full-path`), and translates
    /// the resulting range back into the original `path` index space.
    public func highlightRange(in path: String) -> Range<String.Index>? {
        guard let regex else { return nil }

        if matchFullPath {
            let ns = NSRange(path.startIndex..., in: path)
            guard let m = regex.firstMatch(in: path, options: [], range: ns),
                  let r = Range(m.range, in: path) else { return nil }
            return r
        }

        // Find the basename slice. Drop a trailing `/` first — the
        // printer adds it as directory decoration; the byte isn't
        // part of the name and would shift the regex by one. Then
        // locate the last `/` *within the trimmed region* and take
        // the suffix.
        let endExcludingTrailingSlash: String.Index = path.hasSuffix("/")
            ? path.index(before: path.endIndex)
            : path.endIndex
        let basenameStart: String.Index = {
            let searchRange = path.startIndex..<endExcludingTrailingSlash
            if let slash = path.range(of: "/",
                                      options: .backwards,
                                      range: searchRange)?.lowerBound {
                return path.index(after: slash)
            }
            return path.startIndex
        }()
        guard basenameStart < endExcludingTrailingSlash else { return nil }
        let basename = String(path[basenameStart..<endExcludingTrailingSlash])

        let ns = NSRange(basename.startIndex..., in: basename)
        guard let m = regex.firstMatch(in: basename, options: [], range: ns),
              let r = Range(m.range, in: basename) else { return nil }

        let preLen = basename.distance(from: basename.startIndex,
                                       to: r.lowerBound)
        let matchLen = basename.distance(from: r.lowerBound,
                                         to: r.upperBound)
        let lo = path.index(basenameStart, offsetBy: preLen)
        let hi = path.index(lo, offsetBy: matchLen)
        return lo..<hi
    }

    /// True if this entry should be emitted given its basename and
    /// relative path. The caller passes both because fd matches the
    /// basename by default and the full path under `--full-path`.
    public func matches(basename: String, relativePath: String) -> Bool {
        // Extension filter — applies regardless of pattern, fd-style.
        if !extensions.isEmpty {
            let ext = (basename as NSString).pathExtension.lowercased()
            // `*.tar.gz` style: also try the compound extension.
            var ok = extensions.contains(ext)
            if !ok {
                // fd matches longest-extension first for tarballs etc.
                for candidate in extensions {
                    if basename.lowercased().hasSuffix("." + candidate) {
                        ok = true
                        break
                    }
                }
            }
            if !ok { return false }
        }
        guard let regex else { return true }
        let target = matchFullPath ? relativePath : basename
        let range = NSRange(target.startIndex..., in: target)
        return regex.firstMatch(in: target,
                                options: [],
                                range: range) != nil
    }
}
